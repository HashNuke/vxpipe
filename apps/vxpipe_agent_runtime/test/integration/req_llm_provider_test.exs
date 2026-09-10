defmodule Vxpipe.AgentRuntime.Integration.ReqLLMProviderTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Message,
    ModelRequest,
    ModelResponse,
    ModelTool,
    PendingInvocation
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @moduletag :integration

  test "Gemini accepts an exact tool schema and its running continuation" do
    assert {:ok, config} =
             Provider.new(
               api_key: System.fetch_env!("GEMINI_API_KEY"),
               model: "google:gemini-3.5-flash-lite",
               generation_options: [temperature: 0.0],
               streaming: true
             )

    tool = %ModelTool{
      name: "vxpipe_interop_value",
      description: "Return the fixed interoperability value requested by the caller.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "value" => %{"type" => "string", "enum" => ["vxpipe"]}
        },
        "required" => ["value"],
        "additionalProperties" => false
      }
    }

    messages = [
      Message.system(
        "This is a tool protocol test. Always use the exact supplied tool when requested."
      ),
      Message.user("Call vxpipe_interop_value once with value vxpipe.", :caller)
    ]

    first_request = ModelRequest.new(messages, [tool], [], %{request_id: "interop_first"})

    assert {:ok, %ModelResponse{tool_calls: [call]} = first_response} =
             Provider.stream(config, first_request, &emit_delta("first", &1))

    assert call.name == "vxpipe_interop_value"
    assert call.arguments == %{"value" => "vxpipe"}

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: call.id,
        tool_name: call.name,
        status: :running,
        conversation_mode: :blocking,
        source_turn_id: "turn_interop"
      )

    continuation_messages =
      messages ++
        [
          Message.assistant(first_response.text, [call]),
          Message.tool(call, %{"invocation_id" => call.id, "status" => "running"})
        ]

    continuation_request =
      ModelRequest.new(
        continuation_messages,
        [],
        [pending],
        %{request_id: "interop_continuation"}
      )

    assert {:ok, %ModelResponse{text: text, tool_calls: []}} =
             Provider.stream(config, continuation_request, &emit_delta("continuation", &1))

    assert String.trim(text) != ""
    assert_received {:provider_delta, "continuation", delta} when byte_size(delta) > 0
  end

  defp emit_delta(round, text) do
    send(self(), {:provider_delta, round, text})
    :ok
  end
end
