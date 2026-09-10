defmodule Vxpipe.AgentRuntime.Integration.ReqLLMProviderTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Event,
    Message,
    ModelRequest,
    ModelResponse,
    ModelTool,
    PendingInvocation,
    Result,
    Session
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider

  @moduletag :integration

  test "Gemini accepts an exact tool schema and its running continuation" do
    config = provider_config()

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

    assert {:ok, %ModelResponse{text: text, tool_calls: []} = continuation_response} =
             Provider.stream(config, continuation_request, &emit_delta("continuation", &1))

    assert String.trim(text) != ""
    assert map_size(first_response.usage) > 0 or map_size(continuation_response.usage) > 0
    assert_received {:provider_delta, "continuation", delta} when byte_size(delta) > 0
  end

  test "cancelling a live provider stream leaves its session usable" do
    config = provider_config()

    session =
      start_supervised!(
        {Session,
         instructions: "Follow the caller's formatting request.",
         model_provider: Provider,
         model: config,
         tools: [],
         executor: nil,
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
         event_destination: self(),
         request_timeout_ms: 60_000}
      )

    cancelled =
      Task.async(fn ->
        Session.request(
          session,
          "Write the integers from 1 through 2000 in order, separated by commas.",
          %{request_id: "interop_cancel"}
        )
      end)

    assert_receive {:pending_context_requested, _source, %{request_id: "interop_cancel"}, 1_000}

    assert_receive {:agent_runtime_event,
                    %Event{
                      kind: :text_delta,
                      correlation: %{request_id: "interop_cancel"},
                      data: %{text: text}
                    }},
                   30_000

    assert byte_size(text) > 0
    assert :ok = Session.cancel(session)

    assert {:ok, %Result{status: :cancelled}} = Task.await(cancelled, 5_000)
    assert Session.status(session) == :idle

    next_request =
      Task.async(fn ->
        Session.request(session, "Reply with exactly READY.", %{
          request_id: "interop_after_cancel"
        })
      end)

    assert_receive {:pending_context_requested, _source, %{request_id: "interop_after_cancel"},
                    1_000}

    assert {:ok, %Result{status: :completed, output: output}} =
             Task.await(next_request, 30_000)

    assert String.trim(output) != ""
  end

  defp provider_config do
    assert {:ok, config} =
             Provider.new(
               api_key: System.fetch_env!("GEMINI_API_KEY"),
               model: "google:gemini-3.5-flash-lite",
               generation_options: [temperature: 0.0],
               streaming: true
             )

    config
  end

  defp emit_delta(round, text) do
    send(self(), {:provider_delta, round, text})
    :ok
  end
end
