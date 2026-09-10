defmodule Vxpipe.AgentRuntime.SessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    PendingInvocation,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "runs a deterministic model request outside the session process" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "hello back", test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    assert {:ok, %Result{status: :completed, output: "hello back"}} =
             Session.request(session, "hello", %{request_id: "req_1"})

    assert_receive {:agent_runtime_event,
                    %{kind: :request_started, correlation: %{request_id: "req_1"}}}

    assert_receive {:model_provider_process, provider_pid, request}
    refute provider_pid == session
    assert List.last(request.messages).role == :user
    assert List.last(request.messages).content == "hello"

    assert_receive {:agent_runtime_event,
                    %{kind: :response_completed, correlation: %{request_id: "req_1"}}}

    assert Session.status(session) == :idle
  end

  test "terminating a session terminates its active model request" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :block, test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    caller =
      Task.async(fn ->
        try do
          Session.request(session, "hello", %{request_id: "req_2"})
        catch
          :exit, _reason -> :session_stopped
        end
      end)

    assert_receive {:model_provider_process, provider_pid, request}
    assert List.last(request.messages).content == "hello"
    provider_monitor = Process.monitor(provider_pid)

    GenServer.stop(session, :shutdown)

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider_pid, _reason}
    Task.shutdown(caller, :brutal_kill)
  end

  test "loads current pending invocations in the request worker before generation" do
    {:ok, pending_invocation} =
      PendingInvocation.new(
        invocation_id: "tool_call_1",
        tool_name: "check_balance",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_1"
      )

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "still checking", test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource,
            %{owner: self(), result: {:ok, [pending_invocation]}}},
         pending_context_timeout_ms: 250,
         event_destination: self()}
      )

    assert {:ok, %Result{status: :completed, output: "still checking"}} =
             Session.request(session, "what are the card rules?", %{request_id: "req_3"})

    assert_receive {:pending_context_requested, source_pid, %{request_id: "req_3"}, 250}

    assert_receive {:model_provider_process, provider_pid,
                    %{pending_invocations: [^pending_invocation]}}

    refute source_pid == session
    refute provider_pid == session
  end

  test "fails safely without calling the provider when pending context is unavailable" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "must not run", test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource,
            %{owner: self(), result: {:error, :private_source_failure}}},
         event_destination: self()}
      )

    assert {:ok, %Result{status: :failed, reason: :pending_context_unavailable}} =
             Session.request(session, "hello", %{request_id: "req_4"})

    assert_receive {:pending_context_requested, _source_pid, %{request_id: "req_4"}, 1_000}
    refute_receive {:model_provider_process, _provider_pid, _request}
  end

  test "commits an accepted blocking submission and performs one acknowledgement round" do
    descriptor =
      tool_descriptor(
        "check_balance",
        %{test_owner: self(), identity: :balance, submission: {:accepted, :blocking}}
      )

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :scripted, test_owner: self()},
         tools: [descriptor],
         executor: Vxpipe.AgentRuntime.TestExecutor,
         maximum_model_rounds: 2,
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
         event_destination: self()}
      )

    caller =
      Task.async(fn ->
        Session.request(session, "What is my balance?", %{request_id: "req_tool_1"})
      end)

    assert_receive {:pending_context_requested, first_source, %{request_id: "req_tool_1"}, 1_000}
    send(first_source, {:release, {:ok, []}})

    assert_receive {:model_provider_process, first_provider, first_request}
    assert Enum.map(first_request.messages, & &1.role) == [:system, :user]
    assert [%{name: "check_balance"}] = first_request.tools

    {:ok, call} =
      ToolCall.new(
        id: "tool_call_1",
        name: "check_balance",
        arguments: %{"account_id" => "account_1"}
      )

    {:ok, tool_response} =
      ModelResponse.new(text: "I will check. ", tool_calls: [call])

    send(first_provider, {:test_model_response, {:ok, tool_response}})

    assert_receive {:tool_submitted, executor_pid, :balance, %{"account_id" => "account_1"},
                    %{request_id: "req_tool_1"}, "tool_call_1"}

    refute executor_pid == session

    pending_invocation =
      pending_invocation("tool_call_1", "check_balance", :blocking, "turn_tool_1")

    assert_receive {:pending_context_requested, second_source, %{request_id: "req_tool_1"}, 1_000}

    send(second_source, {:release, {:ok, [pending_invocation]}})

    assert_receive {:model_provider_process, second_provider, second_request}
    assert second_request.pending_invocations == [pending_invocation]
    assert second_request.tools == []
    assert Enum.map(second_request.messages, & &1.role) == [:system, :user, :assistant, :tool]

    tool_message = List.last(second_request.messages)
    assert tool_message.tool_call_id == "tool_call_1"
    assert tool_message.name == "check_balance"

    assert JSON.decode!(tool_message.content) == %{
             "invocation_id" => "tool_call_1",
             "status" => "running"
           }

    {:ok, acknowledgement_response} = ModelResponse.new(text: "I am checking now.")
    send(second_provider, {:test_model_response, {:ok, acknowledgement_response}})

    assert {:ok, %Result{status: :completed, output: "I will check. I am checking now."}} =
             Task.await(caller)
  end

  test "rejects unsupported multiple calls before submitting any work" do
    tools = [
      tool_descriptor(
        "check_balance",
        %{test_owner: self(), identity: :balance, submission: {:accepted, :blocking}}
      ),
      tool_descriptor(
        "check_credit",
        %{test_owner: self(), identity: :credit, submission: {:accepted, :blocking}}
      )
    ]

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :scripted, test_owner: self()},
         tools: tools,
         executor: Vxpipe.AgentRuntime.TestExecutor,
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    caller =
      Task.async(fn ->
        Session.request(session, "Check both", %{request_id: "req_tool_2"})
      end)

    assert_receive {:model_provider_process, provider, _request}

    calls = [
      tool_call("tool_call_1", "check_balance"),
      tool_call("tool_call_2", "check_credit")
    ]

    {:ok, response} = ModelResponse.new(text: "I will check both.", tool_calls: calls)
    send(provider, {:test_model_response, {:ok, response}})

    assert {:ok, {:ok, %Result{status: :failed, reason: :multiple_tool_calls_unsupported}}} =
             Task.yield(caller, 200)

    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _id}
  end

  defp empty_pending_context(owner) do
    {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: owner, result: {:ok, []}}}
  end

  defp pending_invocation(invocation_id, tool_name, conversation_mode, source_turn_id) do
    {:ok, invocation} =
      PendingInvocation.new(
        invocation_id: invocation_id,
        tool_name: tool_name,
        status: :running,
        conversation_mode: conversation_mode,
        source_turn_id: source_turn_id
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

  defp tool_descriptor(name, binding) do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: name,
        description: "Check an account balance",
        input_schema: %{
          "type" => "object",
          "properties" => %{"account_id" => %{"type" => "string"}},
          "required" => ["account_id"],
          "additionalProperties" => false
        },
        binding: binding
      )

    descriptor
  end
end
