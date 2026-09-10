defmodule Vxpipe.AgentRuntime.SessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{PendingInvocation, Result, Session}

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

    assert_receive {:model_provider_process, provider_pid, %{input: "hello"}}
    refute provider_pid == session

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

    assert_receive {:model_provider_process, provider_pid, %{input: "hello"}}
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

  defp empty_pending_context(owner) do
    {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: owner, result: {:ok, []}}}
  end
end
