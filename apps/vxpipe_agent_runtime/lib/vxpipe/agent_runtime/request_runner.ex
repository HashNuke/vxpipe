defmodule Vxpipe.AgentRuntime.RequestRunner do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{
    Conversation,
    Executor,
    Message,
    ModelContext,
    ModelRequest,
    ModelResponse,
    PendingContext,
    Request,
    StreamBudget,
    ToolRegistry
  }

  @spec run(Conversation.t(), Request.t(), map()) ::
          {:ok, String.t(), Conversation.t()} | {:error, atom()}
  def run(%Conversation{} = conversation, %Request{} = request, config) when is_map(config) do
    staged_messages = [Message.user(request.input, request.origin)]

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
           ),
         :ok <- config.emit_model_attempt_started.(),
         {:ok, response} <- generate_observed_response(config, model_request, output) do
      handle_response(
        response,
        conversation,
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

  defp handle_response(
         %ModelResponse{tool_calls: []} = response,
         conversation,
         staged_messages,
         output,
         _round,
         request,
         config
       ) do
    with {:ok, complete_output} <-
           complete_output(response.text, output, config.maximum_output_bytes) do
      conversation =
        commit_final_exchange(response, conversation, staged_messages, request)

      {:ok, complete_output, conversation}
    end
  end

  defp handle_response(response, conversation, staged_messages, output, round, request, config) do
    if round >= config.maximum_model_rounds do
      {:error, :model_round_limit}
    else
      with {:ok, next_output} <-
             append_output(response.text, output, config.maximum_output_bytes),
           {:ok, submissions, blocking?} <- submit_calls(response.tool_calls, request, config),
           conversation <-
             commit_tool_exchange(response, submissions, conversation, staged_messages, request),
           :ok <- config.commit.(conversation) do
        generate(
          conversation,
          [],
          next_output,
          round + 1,
          not blocking?,
          request,
          config
        )
      else
        {:error, reason} when is_atom(reason) -> {:error, reason}
        _invalid -> {:error, :commit_failed}
      end
    end
  end

  defp submit_calls(calls, request, config) do
    with :ok <- validate_call_count(calls, config.maximum_tool_calls_per_round),
         :ok <- validate_unique_call_ids(calls),
         {:ok, resolved_calls} <- resolve_calls(calls, config.tool_registry),
         :ok <- config.begin_submission.() do
      submit_resolved_calls(resolved_calls, request, config)
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

  defp submit_resolved_calls(resolved_calls, request, config) do
    {submissions, blocking?} =
      Enum.reduce(resolved_calls, {[], false}, fn {call, descriptor}, {submissions, blocking?} ->
        case Executor.submit(
               config.executor,
               descriptor.binding,
               call.arguments,
               request.correlation,
               call.id
             ) do
          {:accepted, mode} ->
            {[{call, running_result(call)} | submissions], blocking? or mode == :blocking}

          {:error, reason} ->
            {[{call, rejected_result(reason)} | submissions], blocking?}
        end
      end)

    {:ok, Enum.reverse(submissions), blocking?}
  end

  defp commit_tool_exchange(response, submissions, conversation, staged_messages, request) do
    result_messages = Enum.map(submissions, fn {call, result} -> Message.tool(call, result) end)

    Conversation.append_exchange(
      conversation,
      staged_messages ++
        [Message.assistant(response.text, response.tool_calls)] ++ result_messages,
      request.correlation,
      :durable
    )
  end

  defp commit_final_exchange(response, conversation, staged_messages, request) do
    assistant = Message.assistant(response.text, [])

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
        with :ok <- emit_model_usage(response, config), do: {:ok, response}

      {:error, reason, %ModelResponse{} = response} ->
        with :ok <- emit_model_usage(response, config), do: {:error, reason}

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
        config.emit_text_delta
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

  defp emit_model_usage(%ModelResponse{} = response, config) do
    config.emit_model_usage.(response.usage, response.provider_metadata)
  end

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
