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

  defp handle_response(
         %ModelResponse{tool_calls: [_first, _second | _rest]},
         _conversation,
         _staged_messages,
         _output,
         _round,
         _request,
         _config
       ),
       do: {:error, :multiple_tool_calls_unsupported}

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
    Enum.reduce_while(calls, {:ok, [], false}, fn call, {:ok, submissions, blocking?} ->
      with {:ok, descriptor} <-
             ToolRegistry.resolve(config.tool_registry, call.name, call.arguments),
           {:accepted, mode} <-
             Executor.submit(
               config.executor,
               descriptor.binding,
               call.arguments,
               request.correlation,
               call.id
             ) do
        submission = {call, running_result(call)}
        {:cont, {:ok, [submission | submissions], blocking? or mode == :blocking}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, submissions, blocking?} -> {:ok, Enum.reverse(submissions), blocking?}
      {:error, reason} -> {:error, reason}
    end
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

  defp append_output("", output), do: output
  defp append_output(text, output), do: [text | output]

  defp complete_output(text, output) do
    text
    |> append_output(output)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end
end
