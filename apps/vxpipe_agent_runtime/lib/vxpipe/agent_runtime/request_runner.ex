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
    StreamBudget,
    ToolRegistry
  }

  @tool_result_retry_delay_ms 100

  @spec run(Conversation.t(), Request.t(), map()) ::
          {:ok, String.t() | Dialogue.t(), Conversation.t()}
          | {:ok, Dialogue.t(), Conversation.t(), PendingReplyReplay.t()}
          | {:error, atom()}
  def run(%Conversation{} = conversation, %Request{} = request, config) when is_map(config) do
    staged_messages =
      if config.history_mode == :host_settled,
        do: [],
        else: [Message.user(request.input, request.origin)]

    generate(conversation, staged_messages, [], 1, true, request, config)
  end

  defp generate(
         conversation,
         staged_messages,
         output,
         round,
         tools_enabled?,
         request,
         config
       ) do
    with {:ok, pending_invocations} <- pending_context(config, request.correlation),
         {:ok, model_context} <- model_context(config, request.correlation),
         model_request <-
           ModelRequest.new(
             conversation.messages ++ staged_messages,
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
         {:ok, response} <- generate_round(config, model_request, output, round),
         {:ok, response} <- maybe_correct(response, model_request, round, config) do
      handle_response(
        response,
        prepared_conversation,
        staged_messages,
        output,
        round,
        request,
        config
      )
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _invalid -> {:error, :invalid_provider_response}
    end
  end

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
         config
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

  defp handle_response(response, conversation, staged_messages, output, round, request, config) do
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
              config
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

  defp submit_resolved_calls(resolved_calls, preflight_rejections, request, config) do
    {submissions, disposition} =
      Enum.reduce(resolved_calls, {[], :non_blocking}, fn {call, descriptor},
                                                          {submissions, disposition} ->
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
                 submission_disposition(disposition, mode)}

              {:error, reason} ->
                {[{call, rejected_result(reason)} | submissions], disposition}
            end

          reason ->
            {[{call, rejected_result(reason)} | submissions], disposition}
        end
      end)

    {:ok, Enum.reverse(submissions), disposition}
  end

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
      config.model_provider.generate(config.model, model_request)
    end
  end

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
