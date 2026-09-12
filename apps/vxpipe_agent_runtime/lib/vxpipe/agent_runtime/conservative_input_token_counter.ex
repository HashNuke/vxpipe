defmodule Vxpipe.AgentRuntime.ConservativeInputTokenCounter do
  @moduledoc "Conservative byte-based estimate for normalized model input."

  @behaviour Vxpipe.AgentRuntime.InputTokenCounter

  alias Vxpipe.AgentRuntime.{Message, ModelRequest, ModelTool, PendingInvocation, ToolCall}

  @base_envelope_tokens 256
  @message_envelope_tokens 32
  @tool_envelope_tokens 64

  @impl true
  def count(_state, %ModelRequest{} = request) do
    projected = %{
      "messages" => Enum.map(request.messages, &message/1),
      "model_context" => request.model_context,
      "pending_invocations" => Enum.map(request.pending_invocations, &pending_invocation/1),
      "tools" => Enum.map(request.tools, &tool/1)
    }

    envelope_tokens =
      @base_envelope_tokens +
        length(request.messages) * @message_envelope_tokens +
        length(request.tools) * @tool_envelope_tokens

    {:ok, byte_size(JSON.encode!(projected)) + envelope_tokens}
  rescue
    _error -> {:error, :input_token_count_unavailable}
  end

  defp message(%Message{} = message) do
    %{
      "content" => message.content,
      "name" => message.name,
      "origin" => optional_atom(message.origin),
      "role" => Atom.to_string(message.role),
      "tool_call_id" => message.tool_call_id,
      "tool_calls" => Enum.map(message.tool_calls, &tool_call/1)
    }
  end

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

  defp pending_invocation(%PendingInvocation{} = invocation) do
    %{
      "conversation_mode" => Atom.to_string(invocation.conversation_mode),
      "invocation_id" => invocation.invocation_id,
      "source_turn_id" => invocation.source_turn_id,
      "status" => Atom.to_string(invocation.status),
      "tool_name" => invocation.tool_name
    }
  end

  defp optional_atom(nil), do: nil
  defp optional_atom(value), do: Atom.to_string(value)
end
