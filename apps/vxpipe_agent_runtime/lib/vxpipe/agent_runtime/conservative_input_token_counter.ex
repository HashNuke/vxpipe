defmodule Vxpipe.AgentRuntime.ConservativeInputTokenCounter do
  @moduledoc "Conservative byte-based estimate for normalized model input."

  @behaviour Vxpipe.AgentRuntime.InputTokenCounter

  alias Vxpipe.AgentRuntime.{Dialogue, Message, ModelRequest, ModelTool, ToolCall}

  @base_envelope_tokens 256
  @message_envelope_tokens 32
  @tool_envelope_tokens 64

  @impl true
  def count(_state, %ModelRequest{} = request) do
    projected =
      %{
        "messages" => Enum.map(request.messages, &message/1),
        "model_context" => request.model_context,
        "tools" => Enum.map(request.tools, &tool/1)
      }
      |> put_dialogue_schema(request.reply_protocol)

    envelope_tokens =
      @base_envelope_tokens +
        length(request.messages) * @message_envelope_tokens +
        length(request.tools) * @tool_envelope_tokens

    {:ok, byte_size(JSON.encode!(projected)) + envelope_tokens}
  rescue
    _error -> {:error, :input_token_count_unavailable}
  end

  defp put_dialogue_schema(projected, :mode_message_v1),
    do: Map.put(projected, "response_schema", Dialogue.schema())

  defp put_dialogue_schema(projected, _protocol), do: projected

  defp message(%Message{} = message) do
    %{
      "content" => message.content,
      "name" => message.name,
      "origin" => optional_atom(message.origin),
      "role" => Atom.to_string(message.role),
      "tool_call_id" => message.tool_call_id,
      "tool_calls" => Enum.map(message.tool_calls, &tool_call/1)
    }
    |> put_replay(message.provider_replay)
  end

  defp put_replay(message, replay) when replay == %{}, do: message
  defp put_replay(message, replay), do: Map.put(message, "provider_replay", replay)

  defp tool_call(%ToolCall{} = call) do
    %{
      "arguments" => call.arguments,
      "id" => call.id,
      "name" => call.name,
      "provider_metadata" => call.provider_metadata
    }
  end

  defp tool(%ModelTool{} = tool) do
    %{
      "description" => tool.description,
      "input_schema" => tool.input_schema,
      "name" => tool.name
    }
  end

  defp optional_atom(nil), do: nil
  defp optional_atom(value), do: Atom.to_string(value)
end
