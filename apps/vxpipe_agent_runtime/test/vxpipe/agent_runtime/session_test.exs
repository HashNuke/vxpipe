defmodule Vxpipe.AgentRuntime.SessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Result, Session}

  test "runs a deterministic model request outside the session process" do
    session =
      start_supervised!({Session,
        instructions: "Be concise",
        model_provider: Vxpipe.AgentRuntime.TestModelProvider,
        model: %{reply: "hello back", test_owner: self()},
        event_destination: self()
      })

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
      start_supervised!({Session,
        instructions: "Be concise",
        model_provider: Vxpipe.AgentRuntime.TestModelProvider,
        model: %{mode: :block, test_owner: self()},
        event_destination: self()
      })

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
end
