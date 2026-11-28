defmodule Vxpipe.AgentRuntime.RequestRunner do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{
    CompactionObservation,
    Conversation,
    ContextPreparation,
    Dialogue,
    DialogueRepair,
    Executor,
    Message,
    ModelContext,
    ModelRequest,
    ModelResponse,
    PendingContext,
    PendingReplyReplay,
    Request,
    RoundAdmission,
    RoundCandidate,
    StreamBudget,
    ToolRegistry
  }

  @tool_result_retry_delay_ms 100

  @spec run(Conversation.t(), Request.t(), map()) ::
          {:ok, String.t() | Dialogue.t(), Conversation.t()}
          | {:ok, Dialogue.t(), Conversation.t(), PendingReplyReplay.t()}
          | {:error, atom()}
  def run(%Conversation{} = conversation, %Request{} = request, config) when is_map(config) do
    transient = transient_messages(config)

    staged_messages =
      cond do
        transient != [] -> []
        config.history_mode == :host_settled -> []
        true -> [Message.user(request.input, request.origin)]
      end

    generate(conversation, staged_messages, [], 1, true, request, config)
  end

  defp transient_messages(%{transient_messages: messages}) when is_list(messages), do: messages
  defp transient_messages(_config), do: []

  defp generate(
         conversation,
         staged_messages,
         output,
         round,
         tools_enabled?,
         request,
         config,
         admission_state \\ %{repairs_used: 0, repairs: [], attempt: 1}
       ) do
    with {:ok, pending_invocations} <- pending_context(config, request.correlation),
         {:ok, model_context} <- model_context(config, request.correlation),
         model_request <-
           ModelRequest.new(
             conversation.messages ++
               staged_messages ++
               transient_messages(config) ++
               admission_state.repairs,
             model_tools(config.tool_registry, tools_enabled?),
             pending_invocations,
             model_context,
             request.correlation
           )
           |> Map.put(:reply_protocol, config.reply_protocol)
           |> DialogueRepair.bound(config.reply_repair_policy),
         {:ok, prepared_conversation, model_request} <-
           prepare_context(conversation, model_request, config),
         :ok <- config.emit_model_attempt.(:model_attempt_started),
         {:ok, response, buffered_deltas} <-
           admitted_model_response(config, model_request, output, round),
         {:ok, verdict} <-
           admit_candidate(config, response, request, admission_state, conversation) do
      case verdict do
        {:accept} ->
          accept_round(
            config,
            response,
            buffered_deltas,
            prepared_conversation,
            staged_messages,
            output,
            round,
            request,
            admission_state
          )

        {:accept, %{binds: _binds}} ->
          accept_round(
            config,
            response,
            buffered_deltas,
            prepared_conversation,
            staged_messages,
            output,
            round,
            request,
            admission_state
          )

        {:repair, repair} ->
          handle_admission_repair(
            repair,
            conversation,
            staged_messages,
            output,
            round,
            request,
            config,
            admission_state
          )

        {:failure, reason} ->
          {:error, admission_failure_reason(reason)}
      end
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

  defp admitted_model_response(config, model_request, output, round) do
    if config_round_admission(config) == nil do
      case generate_round(config, model_request, output, round) do
        {:ok, response} ->
          with {:ok, response} <- maybe_correct(response, model_request, round, config) do
            {:ok, response, []}
          end

        {:error, _reason} = error ->
          error
      end
    else
      Process.put(:vxpipe_admission_deltas, [])
      buffered = %{config | emit_text_delta: &buffer_admission_delta/1}

      result =
        with {:ok, response} <- generate_round(buffered, model_request, output, round),
             {:ok, response} <- maybe_correct(response, model_request, round, buffered) do
          {:ok, response}
        end

      deltas = Process.delete(:vxpipe_admission_deltas) || []

      case result do
        {:ok, response} -> {:ok, response, Enum.reverse(deltas)}
        {:error, _reason} = error -> error
      end
    end
  end

  defp buffer_admission_delta(text) when is_binary(text) do
    current = Process.get(:vxpipe_admission_deltas, [])
    Process.put(:vxpipe_admission_deltas, [text | current])
    :ok
  end

  defp accept_round(
         config,
         response,
         buffered_deltas,
         prepared_conversation,
         staged_messages,
         output,
         round,
         request,
         admission_state
       ) do
    # A repaired round must come back tool-free; a disobedient provider tool
    # is rejected without submit/commit/delta effects.
    if admission_state.repairs_used > 0 and response.tool_calls != [] do
      {:error, :guardrail_blocked}
    else
      with :ok <- flush_admitted_deltas(config, buffered_deltas, response) do
        handle_response(
          response,
          prepared_conversation,
          staged_messages,
          output,
          round,
          request,
          config,
          admission_state
        )
      end
    end
  end

  defp flush_admitted_deltas(_config, [], _response), do: :ok

  defp flush_admitted_deltas(config, deltas, response) do
    if deltas_match_response?(deltas, response) do
      flush_deltas(config, deltas)
    else
      # Mismatched streamed deltas are never released; only final admitted
      # speech goes out, once, when it carries caller-facing text.
      case admitted_speech(response) do
        nil -> :ok
        text -> flush_deltas(config, [text])
      end
    end
  end

  defp deltas_match_response?(deltas, %{text: text}) when is_binary(text) do
    try do
      IO.iodata_to_binary(deltas) == text
    rescue
      _error -> false
    end
  end

  defp deltas_match_response?(_deltas, _response), do: false

  defp admitted_speech(%{text: text}) when is_binary(text) do
    if String.trim(text) != "", do: text, else: nil
  end

  defp admitted_speech(_response), do: nil

  defp flush_deltas(_config, []), do: :ok

  defp flush_deltas(config, deltas) do
    Enum.reduce_while(deltas, :ok, fn text, :ok ->
      case config.emit_text_delta.(text) do
        :ok -> {:cont, :ok}
        _unavailable -> {:halt, {:error, :event_unavailable}}
      end
    end)
  end

  defp config_round_admission(%{round_admission: admission}), do: admission
  defp config_round_admission(_config), do: nil

  defp admit_candidate(config, response, request, admission_state, conversation) do
    # Validation before guard checks: malformed or policy-violating shapes
    # fail closed without spending guardrail I/O.
    with :ok <- validate_round_shape(config, response),
         {:ok, candidate} <- build_candidate(config, response, request, admission_state) do
      context = %{
        correlation: request.correlation,
        recent_dialogue:
          if(config_round_admission(config),
            do: Conversation.recent_dialogue(conversation, request.correlation),
            else: {[], false}
          ),
        triggering_input:
          if(request.origin == :caller,
            do: request.input,
            else: Map.get(config, :admission_trigger)
          ),
        history_mode: config.history_mode,
        reply_protocol: config.reply_protocol
      }

      {:ok, RoundAdmission.admit(config_round_admission(config), candidate, context)}
    else
      {:failure, _reason} = failure -> {:ok, failure}
      _invalid -> {:ok, {:failure, :error}}
    end
  end

  defp validate_round_shape(config, response) do
    maximum_calls = Map.get(config, :maximum_tool_calls_per_round, 32)

    cond do
      not is_list(response.tool_calls) ->
        {:failure, :error}

      length(response.tool_calls) > maximum_calls ->
        {:failure, :error}

      not Enum.all?(response.tool_calls, &Vxpipe.AgentRuntime.ToolCall.valid?/1) ->
        {:failure, :error}

      duplicate_tool_ids?(response.tool_calls) ->
        {:failure, :error}

      true ->
        :ok
    end
  end

  defp duplicate_tool_ids?(tool_calls) do
    ids = Enum.map(tool_calls, & &1.id)
    length(ids) != length(Enum.uniq(ids))
  end

  defp build_candidate(config, response, request, admission_state) do
    try do
      {:ok,
       RoundCandidate.new(response.text,
         tool_calls: response.tool_calls,
         correlation: request.correlation,
         attempt: admission_state.attempt,
         maximum_bytes: config.maximum_output_bytes,
         reply_protocol: config.reply_protocol
       )}
    rescue
      ArgumentError -> {:failure, :error}
    catch
      _kind, _reason -> {:failure, :error}
    end
  end

  defp handle_admission_repair(
         repair,
         conversation,
         staged_messages,
         output,
         round,
         request,
         config,
         admission_state
       ) do
    maximum_repairs = Map.get(config, :maximum_admission_repairs, 2)

    if admission_state.repairs_used >= maximum_repairs do
      {:error, :guardrail_blocked}
    else
      repair_text =
        Vxpipe.AgentRuntime.GuardrailFeedback.encode(
          repair.failures || [%{event: :after_turn, messages: repair.messages}]
        )

      if byte_size(repair_text) > config.maximum_model_context_bytes do
        {:error, :guardrail_error}
      else
        repair_message = Message.user(repair_text, :engine)

        generate(
          conversation,
          staged_messages,
          output,
          round,
          false,
          request,
          Map.put(config, :on_feedback_dispatch, Map.get(repair, :on_dispatch)),
          %{
            repairs_used: admission_state.repairs_used + 1,
            repairs: [repair_message],
            attempt: admission_state.attempt + 1
          }
        )
      end
    end
  end

  defp admission_failure_reason(:blocked), do: :guardrail_blocked
  defp admission_failure_reason(:error), do: :guardrail_error
  defp admission_failure_reason(:oversized), do: :guardrail_error
  defp admission_failure_reason(:cancelled), do: :guardrail_cancelled
  defp admission_failure_reason(:stale), do: :guardrail_cancelled
  defp admission_failure_reason(_reason), do: :guardrail_error

  defp generate_round(%{retry_tool_result?: true} = config, request, output, 1) do
    emitted = :atomics.new(1, signed: false)

    observe = fn text ->
      :atomics.put(emitted, 1, 1)
      config.emit_text_delta.(text)
    end

    result = generate_observed_response(%{config | emit_text_delta: observe}, request, output)

    case {result, :atomics.get(emitted, 1)} do
      {{:error, :provider_unavailable}, 0} ->
        # The session owns this worker and its original deadline. Barge-in
        # cancels the backoff and any retry together with the request.
        with :ok <- config.emit_model_attempt.(:model_attempt_failed),
             :ok <- Process.sleep(@tool_result_retry_delay_ms),
             :ok <- config.emit_model_attempt.(:model_attempt_started) do
          generate_observed_response(config, request, output)
        end

      _finished ->
        result
    end
  end

  defp generate_round(config, request, output, _round),
    do: generate_observed_response(config, request, output)

  defp maybe_correct(
         %ModelResponse{tool_calls: []} = response,
         model_request,
         1,
         %{reply_protocol: :mode_message_v1, maximum_model_rounds: rounds} = config
       )
       when rounds > 1 do
    case Dialogue.decode(response.text, config.maximum_output_bytes) do
      {:error, :invalid_dialogue} ->
        with {:ok, repair} <-
               DialogueRepair.prepare(config.reply_repair_policy, model_request, response),
             :ok <- config.emit_model_attempt.(:model_attempt_started),
             {:ok, corrected} <- generate_observed_response(config, repair, []),
             true <- corrected.tool_calls == [],
             {:ok, _dialogue} <- Dialogue.decode(corrected.text, config.maximum_output_bytes) do
          {:ok, corrected}
        else
          false -> {:error, :invalid_dialogue}
          {:error, _reason} = error -> error
        end

      _valid_or_bounded_failure ->
        {:ok, response}
    end
  end

  defp maybe_correct(response, _model_request, _round, _config), do: {:ok, response}

  defp handle_response(
         %ModelResponse{tool_calls: []} = response,
         conversation,
         staged_messages,
         output,
         _round,
         request,
         config,
         _admission_state
       ) do
    with {:ok, complete_output} <- final_output(response.text, output, config) do
      conversation =
        commit_final_exchange(
          response,
          conversation,
          staged_messages,
          request,
          config.history_mode
        )

      case PendingReplyReplay.prepare(response, complete_output, config) do
        nil -> {:ok, complete_output, conversation}
        pending -> {:ok, complete_output, conversation, pending}
      end
    end
  end

  defp handle_response(
         response,
         conversation,
         staged_messages,
         output,
         round,
         request,
         config,
         admission_state
       ) do
    if round >= config.maximum_model_rounds do
      {:error, :model_round_limit}
    else
      with {:ok, next_output} <-
             tool_output(response.text, output, config),
           {:ok, submissions, mode} <- submit_calls(response.tool_calls, request, config),
           conversation <-
             commit_tool_exchange(response, submissions, conversation, staged_messages, request),
           :ok <- config.commit.(conversation) do
        case submission_output(response.text, submissions, mode, config) do
          {:done, reply} ->
            {:ok, reply, conversation}

          :continue ->
            generate(
              conversation,
              [],
              next_output,
              round + 1,
              config.reply_protocol == :mode_message_v1 or mode != :blocking,
              request,
              config,
              %{admission_state | repairs: [], attempt: admission_state.attempt + 1}
            )
        end
      else
        {:error, reason} when is_atom(reason) -> {:error, reason}
        _invalid -> {:error, :commit_failed}
      end
    end
  end

  defp submission_output(text, submissions, mode, %{reply_protocol: :mode_message_v1} = config) do
    if Enum.all?(submissions, fn {_call, result} -> result["status"] == "running" end) do
      {:done, accepted_dialogue(mode, text, config.maximum_output_bytes)}
    else
      :continue
    end
  end

  defp submission_output(_text, _submissions, :await_completion, config),
    do: {:done, silent_output(config.reply_protocol)}

  defp submission_output(_text, _submissions, _mode, _config), do: :continue

  defp accepted_dialogue(:await_completion, _text, _maximum), do: silent_output(:mode_message_v1)

  defp accepted_dialogue(_mode, text, maximum) do
    case Dialogue.decode(text, maximum) do
      {:ok, %Dialogue{agent_mode: :speaker} = preamble} -> preamble
      _ -> silent_output(:mode_message_v1)
    end
  end

  defp silent_output(:mode_message_v1), do: %Dialogue{agent_mode: :listener, message: nil}
  defp silent_output(_protocol), do: ""

  defp submit_calls(calls, request, config) do
    with :ok <- validate_call_count(calls, config.maximum_tool_calls_per_round),
         :ok <- validate_unique_call_ids(calls),
         {:ok, resolved_calls} <- resolve_calls(calls, config.tool_registry),
         {:ok, preflight_rejections} <- preflight_resolved_calls(resolved_calls, request, config),
         :ok <- config.begin_submission.() do
      submit_resolved_calls(resolved_calls, preflight_rejections, request, config)
    end
  end

  defp validate_call_count(calls, maximum) do
    if length(calls) <= maximum, do: :ok, else: {:error, :tool_call_limit}
  end

  defp validate_unique_call_ids(calls) do
    call_ids = Enum.map(calls, & &1.id)

    if length(call_ids) == MapSet.size(MapSet.new(call_ids)) do
      :ok
    else
      {:error, :duplicate_tool_call}
    end
  end

  defp resolve_calls(calls, registry) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, resolved} ->
      case ToolRegistry.resolve(registry, call.name, call.arguments) do
        {:ok, descriptor} -> {:cont, {:ok, [{call, descriptor} | resolved]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, resolved} -> {:ok, Enum.reverse(resolved)}
      {:error, reason} -> {:error, reason}
    end
  end

  # Terminal tools (transfer/hangup, marked via typed host `terminal?` binding)
  # submit last globally, preserving model order within each partition. Ordinary
  # submits complete first, so a blocked ordinary submit delays terminal start.
  # The host `Executor.submit/4` acknowledgement remains the effect-time gate:
  # a terminal denial there becomes a rejected tool result without terminal
  # effects, while already-accepted ordinary submissions stand. After ordinary
  # submits, the host completion barrier (`Executor.await_ordinary_completions/2`,
  # when exported) waits until ordinary invocation results FINISH before any
  # terminal start, including unguarded and tool-only batches. If an ordinary
  # failed (or the wait times out/goes stale), terminal effects are withheld and
  # each terminal call gets a correlated rejected result for a later distinct
  # proposal. No synchronous room query runs here after `begin_submission/0`.
  defp submit_resolved_calls(resolved_calls, preflight_rejections, request, config) do
    {ordinary_calls, terminal_calls} =
      Enum.split_with(resolved_calls, fn {_call, descriptor} -> not terminal_tool?(descriptor) end)

    {ordinary_submissions, disposition, accepted_ordinary_ids} =
      Enum.reduce(ordinary_calls, {[], :non_blocking, []}, fn {call, descriptor},
                                                              {submissions, disposition,
                                                               accepted_ids} ->
        case Map.get(preflight_rejections, call.id) do
          nil ->
            case Executor.submit(
                   config.executor,
                   descriptor.binding,
                   call.arguments,
                   request.correlation,
                   call.id
                 ) do
              {:accepted, mode} ->
                {[{call, running_result(call)} | submissions],
                 submission_disposition(disposition, mode), [call.id | accepted_ids]}

              {:error, reason} ->
                {[{call, rejected_result(reason)} | submissions], disposition, accepted_ids}
            end

          reason ->
            {[{call, rejected_result(reason)} | submissions], disposition, accepted_ids}
        end
      end)

    case terminal_calls do
      [] ->
        {:ok, Enum.reverse(ordinary_submissions), disposition}

      _ ->
        submit_terminal_calls(
          terminal_calls,
          ordinary_submissions,
          disposition,
          Enum.reverse(accepted_ordinary_ids),
          preflight_rejections,
          request,
          config
        )
    end
  end

  defp submit_terminal_calls(
         terminal_calls,
         ordinary_submissions,
         disposition,
         accepted_ordinary_ids,
         preflight_rejections,
         request,
         config
       ) do
    barrier =
      if length(accepted_ordinary_ids) == length(ordinary_submissions),
        do: await_ordinary_barrier(config, request, accepted_ordinary_ids),
        else: {:error, :ordinary_failed}

    case barrier do
      :ok ->
        {submissions, disposition} =
          Enum.reduce(terminal_calls, {ordinary_submissions, disposition}, fn {call, descriptor},
                                                                              {submissions,
                                                                               disposition} ->
            case Map.get(preflight_rejections, call.id) do
              nil ->
                submit_one(call, descriptor, request, config, submissions, disposition)

              reason ->
                {[{call, rejected_result(reason)} | submissions], disposition}
            end
          end)

        {:ok, Enum.reverse(submissions), disposition}

      {:error, reason} ->
        {submissions, _disposition} =
          Enum.reduce(terminal_calls, {ordinary_submissions, disposition}, fn {call, _descriptor},
                                                                              {submissions,
                                                                               disposition} ->
            case Map.get(preflight_rejections, call.id) do
              nil ->
                {[{call, rejected_result(reason)} | submissions], disposition}

              preflight_reason ->
                {[{call, rejected_result(preflight_reason)} | submissions], disposition}
            end
          end)

        {:ok, Enum.reverse(submissions), disposition}
    end
  end

  defp await_ordinary_barrier(_config, _request, []), do: :ok

  defp await_ordinary_barrier(config, request, accepted_ordinary_ids) do
    Executor.await_ordinary_completions(
      config.executor,
      request.correlation,
      accepted_ordinary_ids
    )
  end

  defp submit_one(call, descriptor, request, config, submissions, disposition) do
    case Executor.submit(
           config.executor,
           descriptor.binding,
           call.arguments,
           request.correlation,
           call.id
         ) do
      {:accepted, mode} ->
        {[{call, running_result(call)} | submissions], submission_disposition(disposition, mode)}

      {:error, reason} ->
        {[{call, rejected_result(reason)} | submissions], disposition}
    end
  end

  defp terminal_tool?(%{terminal?: true}), do: true
  defp terminal_tool?(_descriptor), do: false

  # Room admission must stay cancellable while caller interruption waits on the session.
  defp preflight_resolved_calls(resolved_calls, request, config) do
    rejections =
      Enum.reduce(resolved_calls, %{}, fn {call, descriptor}, acc ->
        case Executor.preflight(
               config.executor,
               descriptor.binding,
               call.arguments,
               request.correlation,
               call.id
             ) do
          :ok -> acc
          {:error, reason} -> Map.put(acc, call.id, reason)
        end
      end)

    {:ok, rejections}
  end

  defp submission_disposition(:await_completion, _mode), do: :await_completion
  defp submission_disposition(_previous, :await_completion), do: :await_completion
  defp submission_disposition(:blocking, _mode), do: :blocking
  defp submission_disposition(_previous, mode), do: mode

  defp commit_tool_exchange(response, submissions, conversation, staged_messages, request) do
    result_messages = Enum.map(submissions, fn {call, result} -> Message.tool(call, result) end)

    Conversation.append_exchange(
      conversation,
      staged_messages ++
        [Message.assistant(response.text, response.tool_calls, response.provider_replay)] ++
        result_messages,
      request.correlation,
      :durable
    )
  end

  defp commit_final_exchange(_response, conversation, _staged, _request, :host_settled),
    do: conversation

  defp commit_final_exchange(response, conversation, staged_messages, request, :generated) do
    assistant = Message.assistant(response.text, [], response.provider_replay)

    case {request.origin, staged_messages} do
      {:engine, [_message | _remaining] = messages} ->
        conversation
        |> Conversation.append_exchange(messages, request.correlation, :durable)
        |> Conversation.append_exchange([assistant], request.correlation, :discardable)

      _caller_or_already_committed ->
        Conversation.append_exchange(
          conversation,
          staged_messages ++ [assistant],
          request.correlation,
          :discardable
        )
    end
  end

  defp pending_context(config, correlation) do
    PendingContext.fetch(config.pending_context_source, correlation,
      timeout_ms: config.pending_context_timeout_ms,
      maximum_invocations: config.maximum_pending_invocations
    )
  end

  defp model_context(config, correlation) do
    ModelContext.fetch(config.model_context_source, correlation,
      timeout_ms: config.model_context_timeout_ms,
      maximum_bytes: config.maximum_model_context_bytes
    )
  end

  defp model_tools(_registry, false), do: []
  defp model_tools(registry, true), do: ToolRegistry.model_tools(registry)

  defp prepare_context(conversation, model_request, %{context_preparation: nil}) do
    {:ok, conversation, model_request}
  end

  defp prepare_context(conversation, model_request, config) do
    case ContextPreparation.prepare(conversation, model_request, config.context_preparation) do
      {:ok, prepared} ->
        with :ok <- emit_context_compaction_usage(prepared, config),
             :ok <- commit_compaction(prepared, config) do
          {:ok, prepared.conversation, prepared.request}
        end

      {:error, reason, %CompactionObservation{} = observation} ->
        with :ok <- emit_context_compaction_usage(observation, config) do
          {:error, reason}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp commit_compaction(%{compaction: nil}, _config), do: :ok
  defp commit_compaction(%{conversation: conversation}, config), do: config.commit.(conversation)

  defp emit_context_compaction_usage(%{compaction: nil}, _config), do: :ok

  defp emit_context_compaction_usage(%{compaction: compaction}, config) do
    compaction
    |> CompactionObservation.from_result(:succeeded)
    |> emit_context_compaction_usage(config)
  end

  defp emit_context_compaction_usage(%CompactionObservation{} = observation, config) do
    config.emit_context_compaction_usage.(
      observation.usage,
      observation.provider_metadata,
      observation.outcome
    )
  end

  defp generate_response(config, model_request, output) do
    try do
      case provider_response(config, model_request, output) do
        {:runtime_error, reason} ->
          {:error, reason}

        {:runtime_error, reason, %ModelResponse{} = response} ->
          if ModelResponse.valid?(response) do
            {:error, reason, response}
          else
            {:error, :invalid_provider_response}
          end

        {:ok, %ModelResponse{} = response} ->
          if ModelResponse.valid?(response) do
            {:ok, response}
          else
            {:error, :invalid_provider_response}
          end

        {:error, :invalid_provider_response} ->
          {:error, :invalid_provider_response}

        {:error, _reason} ->
          {:error, :provider_unavailable}

        _invalid ->
          {:error, :invalid_provider_response}
      end
    rescue
      _error -> {:error, :provider_unavailable}
    catch
      _kind, _reason -> {:error, :provider_unavailable}
    end
  end

  defp generate_observed_response(config, model_request, output) do
    case generate_response(config, model_request, output) do
      {:ok, %ModelResponse{} = response} ->
        with :ok <- emit_model_usage(response, config, :succeeded), do: {:ok, response}

      {:error, reason, %ModelResponse{} = response} ->
        with :ok <- emit_model_usage(response, config, :failed), do: {:error, reason}

      {:error, _reason} = error ->
        error
    end
  end

  defp provider_response(config, model_request, output) do
    if streaming_provider?(config) do
      stream_response(config, model_request, output)
    else
      confirm_feedback_dispatch(config)
      config.model_provider.generate(config.model, model_request)
    end
  end

  defp confirm_feedback_dispatch(%{on_feedback_dispatch: callback}) when is_function(callback, 0),
    do: callback.()

  defp confirm_feedback_dispatch(_config), do: :ok

  defp streaming_provider?(config) do
    function_exported?(config.model_provider, :stream, 3) and
      (not function_exported?(config.model_provider, :streaming?, 1) or
         config.model_provider.streaming?(config.model))
  end

  defp stream_response(config, model_request, output) do
    remaining_output_bytes = config.maximum_output_bytes - IO.iodata_length(output)

    budget =
      StreamBudget.new(
        remaining_output_bytes,
        config.maximum_stream_events_per_round,
        stream_emitter(config)
      )

    confirm_feedback_dispatch(config)

    response =
      config.model_provider.stream(config.model, model_request, &StreamBudget.emit(budget, &1))

    case {StreamBudget.outcome(budget), response} do
      {:ok, response} ->
        response

      {{:error, reason}, {:ok, %ModelResponse{} = response}} ->
        {:runtime_error, reason, response}

      {{:error, reason}, _response} ->
        {:runtime_error, reason}
    end
  end

  defp emit_model_usage(%ModelResponse{} = response, config, outcome) do
    config.emit_model_usage.(response.usage, response.provider_metadata, outcome)
  end

  defp stream_emitter(%{reply_protocol: :mode_message_v1}), do: fn _text -> :ok end
  defp stream_emitter(config), do: config.emit_text_delta

  defp final_output(text, _output, %{reply_protocol: :mode_message_v1} = config),
    do: Dialogue.decode(text, config.maximum_output_bytes)

  defp final_output(text, output, config),
    do: complete_output(text, output, config.maximum_output_bytes)

  defp tool_output(_text, _output, %{reply_protocol: :mode_message_v1}), do: {:ok, []}

  defp tool_output(text, output, config),
    do: append_output(text, output, config.maximum_output_bytes)

  defp running_result(call),
    do: %{"invocation_id" => call.id, "status" => "running"}

  defp rejected_result(reason),
    do: %{"reason" => Atom.to_string(reason), "status" => "rejected"}

  defp append_output("", output, _maximum_bytes), do: {:ok, output}

  defp append_output(text, output, maximum_bytes) do
    next_output = [text | output]

    if IO.iodata_length(next_output) <= maximum_bytes do
      {:ok, next_output}
    else
      {:error, :output_too_large}
    end
  end

  defp complete_output(text, output, maximum_bytes) do
    with {:ok, complete_output} <- append_output(text, output, maximum_bytes) do
      {:ok, complete_output |> Enum.reverse() |> IO.iodata_to_binary()}
    end
  end
end
