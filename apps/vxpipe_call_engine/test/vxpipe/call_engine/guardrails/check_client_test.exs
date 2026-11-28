defmodule Vxpipe.CallEngine.Guardrails.CheckClientTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Guardrails.CheckClient

  defmodule ScriptedGuardrails do
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

    @impl true
    def init(owner), do: {:ok, owner}

    @impl true
    def handle_call({:check, event, proposal_id, evidence, deadline_ms}, _from, owner) do
      send(owner, {:guardrails_check_issued, event, proposal_id, evidence, deadline_ms})

      receive do
        {:guardrails_reply, reply} -> {:reply, reply, owner}
      after
        5_000 -> {:reply, {:error, :timeout}, owner}
      end
    end
  end

  test "a passing check returns passed with the evaluated evidence" do
    owner = self()
    server = start_supervised!({ScriptedGuardrails, owner})
    deadline = System.monotonic_time(:millisecond) + 2_000

    task =
      Task.async(fn ->
        CheckClient.check(
          server,
          :before_outgoing_transfer,
          "transfer-1",
          %{"destination" => "billing"},
          deadline
        )
      end)

    assert_receive {:guardrails_check_issued, :before_outgoing_transfer, "transfer-1", evidence,
                    ^deadline}

    assert evidence["destination"] == "billing"
    send(server, {:guardrails_reply, :passed})
    assert :passed = Task.await(task)
  end

  test "blocked lines pass through untouched" do
    owner = self()
    server = start_supervised!({ScriptedGuardrails, owner})
    deadline = System.monotonic_time(:millisecond) + 2_000

    task =
      Task.async(fn ->
        CheckClient.check(server, :after_turn, "attempt-1", %{}, deadline)
      end)

    assert_receive {:guardrails_check_issued, :after_turn, "attempt-1", _, _}
    send(server, {:guardrails_reply, {:blocked, ["Line one.", "Line two."]}})
    assert {:blocked, ["Line one.", "Line two."]} = Task.await(task)
  end

  test "a dead server fences to cancelled and never raises" do
    server = start_supervised!({ScriptedGuardrails, self()})
    stop_supervised!(ScriptedGuardrails)

    assert {:error, :cancelled} =
             CheckClient.check(
               server,
               :after_turn,
               "attempt-1",
               %{},
               System.monotonic_time(:millisecond) + 2_000
             )
  end

  test "an elapsed deadline fails without issuing the call" do
    owner = self()
    server = start_supervised!({ScriptedGuardrails, owner})

    assert {:error, :timeout} =
             CheckClient.check(
               server,
               :after_turn,
               "attempt-1",
               %{},
               System.monotonic_time(:millisecond) - 1
             )

    refute_received {:guardrails_check_issued, _, _, _, _}
  end

  test "malformed service replies map to invalid_result" do
    owner = self()
    server = start_supervised!({ScriptedGuardrails, owner})
    deadline = System.monotonic_time(:millisecond) + 2_000

    task =
      Task.async(fn -> CheckClient.check(server, :after_turn, "attempt-1", %{}, deadline) end)

    assert_receive {:guardrails_check_issued, _, _, _, _}
    send(server, {:guardrails_reply, {:blocked, :oops}})
    assert {:error, :invalid_result} = Task.await(task)
  end
end
