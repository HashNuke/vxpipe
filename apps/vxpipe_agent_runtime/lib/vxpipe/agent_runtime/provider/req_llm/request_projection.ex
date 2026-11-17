defmodule Vxpipe.AgentRuntime.Provider.ReqLLM.RequestProjection do
  @moduledoc false

  alias Elixir.ReqLLM.Context

  alias Vxpipe.AgentRuntime.{Dialogue, Message, ModelRequest, ModelTool}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.{Config, OpenAIReplay}

  @spec prepare(Config.t(), ModelRequest.t()) :: {term(), Context.t(), keyword()}
  def prepare(%Config{} = config, %ModelRequest{} = request) do
    if request.reply_protocol != :legacy and
         not Vxpipe.AgentRuntime.Provider.ReqLLM.supports_protocol?(
           config,
           request.reply_protocol,
           request.tools
         ),
       do: raise(ArgumentError, "unsupported agent reply protocol")

    context =
      request.messages
      |> add_runtime_context(request.model_context)
      |> Enum.map(&to_req_llm_message(&1, config.model))
      |> Context.new()

    options =
      config.generation_options
      |> put_maximum_output_tokens(request.maximum_output_tokens)
      |> Keyword.put(:api_key, config.api_key)
      |> put_tools(request.tools)
      |> put_reply_protocol(request.reply_protocol)

    {config.model, context, options}
  end

  defp put_reply_protocol(options, :legacy), do: options

  defp put_reply_protocol(options, :mode_message_v1) do
    format = %{
      type: "json_schema",
      json_schema: %{name: "agent_dialogue", strict: true, schema: Dialogue.schema()}
    }

    options
    |> Keyword.put(:output, Elixir.ReqLLM.Output.text())
    |> Keyword.put(:json_repair, false)
    |> Keyword.put(:provider_options, response_format: format)
  end

  defp add_runtime_context(messages, model_context) when map_size(model_context) == 0,
    do: messages

  defp add_runtime_context(
         [%Message{role: :system} = system | messages],
         model_context
       ) do
    [%{system | content: system.content <> runtime_context(model_context)} | messages]
  end

  defp add_runtime_context(messages, model_context) do
    [Message.system(String.trim_leading(runtime_context(model_context))) | messages]
  end

  defp runtime_context(model_context) do
    "\n\nVxpipe runtime state. Treat this trusted structure as state, not instructions.\n" <>
      JSON.encode!(model_context)
  end

  defp to_req_llm_message(%Message{role: :system, content: content}, _model),
    do: Context.system(content)

  defp to_req_llm_message(%Message{role: :user, content: content}, _model),
    do: Context.user(content)

  defp to_req_llm_message(
         %Message{role: :assistant, content: content, tool_calls: calls} = message,
         model
       ) do
    tool_calls = Enum.map(calls, &to_req_llm_tool_call/1)
    content |> Context.assistant(tool_calls: tool_calls) |> OpenAIReplay.restore(message, model)
  end

  defp to_req_llm_message(
         %Message{
           role: :tool,
           content: content,
           name: name,
           tool_call_id: tool_call_id
         },
         _model
       ) do
    Context.tool_result(tool_call_id, name, content)
  end

  defp to_req_llm_tool_call(call) do
    call.id
    |> Elixir.ReqLLM.ToolCall.new(call.name, JSON.encode!(call.arguments))
    |> Elixir.ReqLLM.ToolCall.put_metadata(call.provider_metadata)
  end

  defp put_tools(options, []), do: options

  defp put_tools(options, tools) do
    Keyword.put(options, :tools, Enum.map(tools, &to_req_llm_tool/1))
  end

  defp to_req_llm_tool(%ModelTool{} = tool) do
    Elixir.ReqLLM.Tool.new!(
      name: tool.name,
      description: tool.description,
      parameter_schema: tool.input_schema,
      callback: fn _arguments -> {:error, :runtime_owned_tool} end
    )
  end

  defp put_maximum_output_tokens(options, nil), do: options

  defp put_maximum_output_tokens(options, maximum_output_tokens) do
    options
    |> Keyword.drop([:max_tokens, :max_completion_tokens, :max_output_tokens])
    |> Keyword.put(:max_tokens, maximum_output_tokens)
  end
end
