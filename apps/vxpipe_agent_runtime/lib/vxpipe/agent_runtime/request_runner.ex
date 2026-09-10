defmodule Vxpipe.AgentRuntime.RequestRunner do
  @moduledoc false

  alias Vxpipe.AgentRuntime.{
    Conversation,
    Executor,
    Message,
    ModelRequest,
    ModelResponse,
    PendingContext,
    Request,
    ToolRegistry
  }

  @spec run(Conversation.t(), Request.t(), map()) ::
          {:ok, String.t(), Conversation.t()} | {:error, atom()}
  def run(%Conversation{} = conversation, %Request{} = request, config) when is_map(config) do
    staged_messages = [Message.user(request.input)]

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
         model_request <-
           ModelRequest.new(
             conversation.messages ++ staged_messages,
             model_tools(config.tool_registry, tools_enabled?),
             pending_invocations,
             request.correlation
           ),
         {:ok, %ModelResponse{} = response} <-
           config.model_provider.generate(config.model, model_request),
         true <- ModelResponse.valid?(response) do
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
         _request,
         _config
       ) do
    conversation =
      Conversation.append(conversation, staged_messages ++ [Message.assistant(response.text, [])])

    {:ok, complete_output(response.text, output), conversation}
  end

  defp handle_response(response, conversation, staged_messages, output, round, request, config) do
    if round >= config.maximum_model_rounds do
      {:error, :model_round_limit}
    else
      with {:ok, submissions, blocking?} <- submit_calls(response.tool_calls, request, config),
           conversation <-
             commit_tool_exchange(response, submissions, conversation, staged_messages),
           :ok <- config.commit.(conversation) do
        generate(
          conversation,
          [],
          append_output(response.text, output),
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
    with :ok <- validate_unique_call_ids(calls),
         {:ok, resolved_calls} <- resolve_calls(calls, config.tool_registry) do
      submit_resolved_calls(resolved_calls, request, config)
    end
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

  defp commit_tool_exchange(response, submissions, conversation, staged_messages) do
    result_messages = Enum.map(submissions, fn {call, result} -> Message.tool(call, result) end)

    Conversation.append(
      conversation,
      staged_messages ++
        [Message.assistant(response.text, response.tool_calls)] ++ result_messages
    )
  end

  defp pending_context(config, correlation) do
    PendingContext.fetch(config.pending_context_source, correlation,
      timeout_ms: config.pending_context_timeout_ms,
      maximum_invocations: config.maximum_pending_invocations
    )
  end

  defp model_tools(_registry, false), do: []
  defp model_tools(registry, true), do: ToolRegistry.model_tools(registry)

  defp running_result(call),
    do: %{"invocation_id" => call.id, "status" => "running"}

  defp rejected_result(reason),
    do: %{"reason" => Atom.to_string(reason), "status" => "rejected"}

  defp append_output("", output), do: output
  defp append_output(text, output), do: [text | output]

  defp complete_output(text, output) do
    text
    |> append_output(output)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end
end
