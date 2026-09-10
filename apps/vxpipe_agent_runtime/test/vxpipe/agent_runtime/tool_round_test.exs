defmodule Vxpipe.AgentRuntime.ToolRoundTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    PendingInvocation,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "commits an accepted blocking submission and performs one acknowledgement round" do
    session = start_session([tool_descriptor("check_balance", :balance, :blocking)])
    caller = request(session, "What is my balance?", "req_tool_1")

    release_pending_context("req_tool_1", [])

    assert_receive {:model_provider_process, first_provider, first_request}
    assert Enum.map(first_request.messages, & &1.role) == [:system, :user]
    assert [%{name: "check_balance"}] = first_request.tools

    reply_with_tools(first_provider, "I will check. ", [
      tool_call("tool_call_1", "check_balance")
    ])

    assert_submission(:balance, "tool_call_1", "req_tool_1")

    pending_invocation = pending_invocation("tool_call_1", "check_balance", :blocking)
    release_pending_context("req_tool_1", [pending_invocation])

    assert_receive {:model_provider_process, second_provider, second_request}
    assert second_request.pending_invocations == [pending_invocation]
    assert second_request.tools == []
    assert Enum.map(second_request.messages, & &1.role) == [:system, :user, :assistant, :tool]
    assert running_result(List.last(second_request.messages)) == "tool_call_1"

    reply_with_text(second_provider, "I am checking now.")

    assert {:ok, %Result{status: :completed, output: "I will check. I am checking now."}} =
             Task.await(caller)
  end

  test "commits accepted and rejected calls in provider order" do
    session =
      start_session([
        tool_descriptor("check_balance", :balance, :blocking),
        tool_descriptor("check_credit", :credit, {:error, :saturated})
      ])

    caller = request(session, "Check both", "req_tool_2")
    release_pending_context("req_tool_2", [])

    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, "I will check both. ", [
      tool_call("tool_call_1", "check_balance"),
      tool_call("tool_call_2", "check_credit")
    ])

    assert_submission(:balance, "tool_call_1", "req_tool_2")
    assert_submission(:credit, "tool_call_2", "req_tool_2")

    pending_invocation = pending_invocation("tool_call_1", "check_balance", :blocking)
    release_pending_context("req_tool_2", [pending_invocation])

    assert_receive {:model_provider_process, second_provider, second_request}
    assert second_request.tools == []

    result_messages = Enum.filter(second_request.messages, &(&1.role == :tool))
    assert Enum.map(result_messages, & &1.tool_call_id) == ["tool_call_1", "tool_call_2"]

    assert Enum.map(result_messages, &JSON.decode!(&1.content)) == [
             %{"invocation_id" => "tool_call_1", "status" => "running"},
             %{"reason" => "saturated", "status" => "rejected"}
           ]

    reply_with_text(second_provider, "One is running and one is busy.")
    assert {:ok, %Result{status: :completed}} = Task.await(caller)
  end

  test "keeps tools available after an explicitly non-blocking submission" do
    session = start_session([tool_descriptor("check_balance", :balance, :non_blocking)])
    caller = request(session, "Check it", "req_tool_3")
    release_pending_context("req_tool_3", [])

    assert_receive {:model_provider_process, provider, _request}
    reply_with_tools(provider, "I will check.", [tool_call("tool_call_3", "check_balance")])
    assert_submission(:balance, "tool_call_3", "req_tool_3")

    pending_invocation = pending_invocation("tool_call_3", "check_balance", :non_blocking)
    release_pending_context("req_tool_3", [pending_invocation])

    assert_receive {:model_provider_process, second_provider, second_request}
    assert [%{name: "check_balance"}] = second_request.tools
    reply_with_text(second_provider, "Ask me something else while I check.")

    assert {:ok, %Result{status: :completed}} = Task.await(caller)
  end

  defp start_session(tools) do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       model_provider: Vxpipe.AgentRuntime.TestModelProvider,
       model: %{mode: :scripted, test_owner: self()},
       tools: tools,
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

  defp reply_with_tools(provider, text, calls) do
    {:ok, response} = ModelResponse.new(text: text, tool_calls: calls)
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp reply_with_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp assert_submission(identity, invocation_id, request_id) do
    assert_receive {:tool_submitted, executor, ^identity, %{"account_id" => "account_1"},
                    %{request_id: ^request_id}, ^invocation_id}

    refute executor == self()
  end

  defp running_result(message) do
    assert message.name == "check_balance"

    assert %{"invocation_id" => invocation_id, "status" => "running"} =
             JSON.decode!(message.content)

    invocation_id
  end

  defp pending_invocation(invocation_id, tool_name, conversation_mode) do
    {:ok, invocation} =
      PendingInvocation.new(
        invocation_id: invocation_id,
        tool_name: tool_name,
        status: :running,
        conversation_mode: conversation_mode,
        source_turn_id: "turn_1"
      )

    invocation
  end

  defp tool_call(invocation_id, name) do
    {:ok, call} =
      ToolCall.new(
        id: invocation_id,
        name: name,
        arguments: %{"account_id" => "account_1"}
      )

    call
  end

  defp tool_descriptor(name, identity, submission) do
    submission =
      case submission do
        mode when mode in [:blocking, :non_blocking] -> {:accepted, mode}
        {:error, _reason} = error -> error
      end

    {:ok, descriptor} =
      ToolDescriptor.new(
        name: name,
        description: "Check an account value",
        input_schema: %{
          "type" => "object",
          "properties" => %{"account_id" => %{"type" => "string"}},
          "required" => ["account_id"],
          "additionalProperties" => false
        },
        binding: %{test_owner: self(), identity: identity, submission: submission}
      )

    descriptor
  end
end
