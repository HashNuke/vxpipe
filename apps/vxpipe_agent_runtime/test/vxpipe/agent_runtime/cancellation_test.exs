defmodule Vxpipe.AgentRuntime.CancellationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    PendingInvocation,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "cancels provisional provider work and leaves the session usable" do
    session = start_session([])
    caller = request(session, "discard me", "req_cancel_1")

    release_pending_context("req_cancel_1", [])
    assert_receive {:model_provider_process, provider, _request}
    provider_monitor = Process.monitor(provider)

    assert :ok = Session.cancel(session)
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
    assert {:ok, %Result{status: :cancelled}} = Task.await(caller)
    assert Session.status(session) == :idle

    next_caller = request(session, "keep me", "req_cancel_2")
    release_pending_context("req_cancel_2", [])
    assert_receive {:model_provider_process, next_provider, next_request}
    assert Enum.map(next_request.messages, & &1.role) == [:system, :user]
    assert List.last(next_request.messages).content == "keep me"

    reply_with_text(next_provider, "kept")
    assert {:ok, %Result{status: :completed, output: "kept"}} = Task.await(next_caller)
  end

  test "defers cancellation across submission until the running exchange commits" do
    descriptor =
      tool_descriptor({:await_release, {:accepted, :non_blocking}})

    session = start_session([descriptor])
    caller = request(session, "Check my balance", "req_cancel_tool_1")
    release_pending_context("req_cancel_tool_1", [])

    assert_receive {:model_provider_process, provider, _request}
    reply_with_tool(provider)

    assert_receive {:tool_submitted, executor, :balance, _arguments, _context, "tool_call_1"}

    cancel_task = Task.async(fn -> Session.cancel(session) end)
    _ = :sys.get_state(session)
    assert Task.yield(cancel_task, 0) == nil

    send(executor, :release_submission)

    assert :ok = Task.await(cancel_task)
    assert {:ok, %Result{status: :cancelled}} = Task.await(caller)

    pending_invocation = pending_invocation()
    next_caller = request(session, "What are the card rules?", "req_cancel_tool_2")
    release_pending_context("req_cancel_tool_2", [pending_invocation])

    assert_receive {:model_provider_process, next_provider, next_request}

    assert Enum.map(next_request.messages, & &1.role) == [
             :system,
             :user,
             :assistant,
             :tool,
             :user
           ]

    assert running_messages(next_request) == ["tool_call_1"]
    reply_with_text(next_provider, "The rules are available.")
    assert {:ok, %Result{status: :completed}} = Task.await(next_caller)
  end

  defp start_session(tools) do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       model_provider: Vxpipe.AgentRuntime.TestModelProvider,
       model: %{mode: :scripted, test_owner: self()},
       tools: tools,
       executor: if(tools == [], do: nil, else: Vxpipe.AgentRuntime.TestExecutor),
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

  defp reply_with_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
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

  defp tool_descriptor(submission) do
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
        binding: %{test_owner: self(), identity: :balance, submission: submission}
      )

    descriptor
  end
end
