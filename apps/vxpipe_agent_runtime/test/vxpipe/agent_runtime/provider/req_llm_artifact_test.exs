defmodule Vxpipe.AgentRuntime.Provider.ReqLLMArtifactTest do
  use ExUnit.Case, async: true

  alias Elixir.ReqLLM.{Context, Response, ToolCall}
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.ResponseNormalizer

  test "buffered native calls cannot masquerade as Google stream artifacts" do
    text = ~s({"agent_mode":"speaker","message":"Hello."})
    call = ToolCall.new("real-buffered-call", "structured_output", text)

    response = %Response{
      id: "buffered",
      model: "google:gemini-3.5-flash-lite",
      context: Context.new(),
      message: Context.assistant(text, tool_calls: [call]),
      finish_reason: :tool_calls
    }

    assert {:ok, %{tool_calls: [_]}} = ResponseNormalizer.normalize(response)

    assert {:error, :invalid_provider_response} =
             ResponseNormalizer.normalize(response, :mode_message_v1)
  end
end
