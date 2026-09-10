defmodule Vxpipe.AgentRuntime.UsageEventTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Event, ModelResponse, Result, Session}

  test "emits safe usage metadata for a completed provider round" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :scripted, test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
         event_destination: self()}
      )

    caller =
      Task.async(fn -> Session.request(session, "Hello", %{request_id: "req_usage_1"}) end)

    assert_receive {:pending_context_requested, source, %{request_id: "req_usage_1"}, 1_000}
    send(source, {:release, {:ok, []}})
    assert_receive {:model_provider_process, provider, _request}

    {:ok, response} =
      ModelResponse.new(
        text: "Hello.",
        usage: %{input_tokens: 4, output_tokens: 2},
        provider_metadata: %{request_id: "provider_request_1", model: "fixture-model"}
      )

    send(provider, {:test_model_response, {:ok, response}})

    assert_receive {:agent_runtime_event,
                    %Event{
                      kind: :model_usage,
                      correlation: %{request_id: "req_usage_1"},
                      data: %{
                        usage: %{input_tokens: 4, output_tokens: 2},
                        provider_metadata: %{
                          request_id: "provider_request_1",
                          model: "fixture-model"
                        }
                      }
                    } = event}

    refute inspect(event) =~ "provider_request_1"
    assert {:ok, %Result{status: :completed, output: "Hello."}} = Task.await(caller)
  end
end
