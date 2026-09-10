defmodule Vxpipe.AgentRuntime.ConversationRecoveryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    PendingInvocation,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "retains an accepted running exchange when its acknowledgement request fails" do
    session = start_session()
    first_caller = request(session, "Check my balance", "req_1")
    release_pending_context("req_1", [])

    assert_receive {:model_provider_process, first_provider, _request}
    reply_with_tool(first_provider)

    assert_receive {:tool_submitted, _executor, :balance, _arguments, _context, "tool_call_1"}

    pending_invocation = pending_invocation()
    release_pending_context("req_1", [pending_invocation])

    assert_receive {:model_provider_process, acknowledgement_provider, acknowledgement_request}
    assert running_messages(acknowledgement_request) == ["tool_call_1"]

    send(
      acknowledgement_provider,
      {:test_model_response, {:error, :raw_provider_failure_that_must_not_escape}}
    )

    assert {:ok, %Result{status: :failed, reason: :provider_unavailable}} =
             Task.await(first_caller)

    second_caller = request(session, "What are the card rules?", "req_2")
    release_pending_context("req_2", [pending_invocation])

    assert_receive {:model_provider_process, second_provider, second_request}

    assert Enum.map(second_request.messages, & &1.role) == [
             :system,
             :user,
             :assistant,
             :tool,
             :user
           ]

    assert running_messages(second_request) == ["tool_call_1"]
    assert second_request.pending_invocations == [pending_invocation]

    {:ok, final_response} = ModelResponse.new(text: "The card rules are available.")
    send(second_provider, {:test_model_response, {:ok, final_response}})

    assert {:ok, %Result{status: :completed, output: "The card rules are available."}} =
             Task.await(second_caller)
  end

  defp start_session do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       model_provider: Vxpipe.AgentRuntime.TestModelProvider,
       model: %{mode: :scripted, test_owner: self()},
       tools: [tool_descriptor()],
       executor: Vxpipe.AgentRuntime.TestExecutor,
       maximum_model_rounds: 2,
       pending_context_source:
         {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
       event_destination: self()}
    )
  end

  defp request(session, text, request_id) do
    Task.async(fn -> Session.request(session, text, %{request_id: request_id}) end)
  end

  defp release_pending_context(request_id, invocations) do
    assert_receive {:pending_context_requested, source, %{request_id: ^request_id}, 1_000}
    send(source, {:release, {:ok, invocations}})
  end

  defp reply_with_tool(provider) do
    {:ok, call} =
      ToolCall.new(
        id: "tool_call_1",
        name: "check_balance",
        arguments: %{"account_id" => "account_1"}
      )

    {:ok, response} = ModelResponse.new(text: "I will check.", tool_calls: [call])
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp running_messages(request) do
    request.messages
    |> Enum.filter(&(&1.role == :tool))
    |> Enum.map(&JSON.decode!(&1.content))
    |> Enum.filter(&(&1["status"] == "running"))
    |> Enum.map(& &1["invocation_id"])
  end

  defp pending_invocation do
    {:ok, invocation} =
      PendingInvocation.new(
        invocation_id: "tool_call_1",
        tool_name: "check_balance",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_1"
      )

    invocation
  end

  defp tool_descriptor do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: "check_balance",
        description: "Check an account balance",
        input_schema: %{
          "type" => "object",
          "properties" => %{"account_id" => %{"type" => "string"}},
          "required" => ["account_id"],
          "additionalProperties" => false
        },
        binding: %{
          test_owner: self(),
          identity: :balance,
          submission: {:accepted, :non_blocking}
        }
      )

    descriptor
  end
end
