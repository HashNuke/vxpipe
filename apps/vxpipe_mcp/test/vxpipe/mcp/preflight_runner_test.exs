defmodule Vxpipe.MCP.PreflightRunnerTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.PreflightRunner

  setup do
    tasks = start_supervised!({Task.Supervisor, name: nil})

    runner =
      start_supervised!(
        {PreflightRunner, name: nil, task_supervisor: tasks, limit: 1, timeout: 50, interval: 0}
      )

    %{runner: runner, tasks: tasks}
  end

  test "returns results and bounds simultaneous probes", %{runner: runner, tasks: tasks} do
    owner = self()

    pending =
      Task.Supervisor.async_nolink(tasks, fn ->
        PreflightRunner.run(runner, "tenant", fn ->
          send(owner, {:worker, self()})

          receive do
            :finish -> {:ok, :done}
          end
        end)
      end)

    assert_receive {:worker, worker}

    assert {:error, :mcp_connection_busy} =
             PreflightRunner.run(runner, "other", fn -> flunk("must not start") end)

    send(worker, :finish)
    assert {:ok, :done} = Task.await(pending)
    assert {:ok, :next} = PreflightRunner.run(runner, "tenant", fn -> {:ok, :next} end)
  end

  test "deadline kills the probe and returns a redacted timeout", %{runner: runner} do
    owner = self()

    assert {:error, :mcp_connection_timed_out} =
             PreflightRunner.run(runner, "tenant", fn ->
               send(owner, {:worker, self()})

               receive do
                 :never -> :ok
               end
             end)

    assert_receive {:worker, worker}
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}
  end

  test "caller death cancels the worker", %{runner: runner, tasks: tasks} do
    owner = self()

    caller =
      Task.Supervisor.async_nolink(tasks, fn ->
        PreflightRunner.run(runner, "tenant", fn ->
          send(owner, {:worker, self()})

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive {:worker, worker}
    ref = Process.monitor(worker)
    Task.shutdown(caller, :brutal_kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}
  end

  test "a queued success cannot be accepted after the overall deadline", %{tasks: tasks} do
    runner =
      start_supervised!(
        {PreflightRunner, name: nil, task_supervisor: tasks, timeout: 250, interval: 0},
        id: :deadline_runner
      )

    owner = self()

    caller =
      Task.Supervisor.async_nolink(tasks, fn ->
        PreflightRunner.run(runner, "tenant", fn ->
          send(owner, {:worker, self()})

          receive do
            :finish -> {:ok, :late}
          end
        end)
      end)

    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    :ok = :sys.suspend(runner)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 1_000
    Process.send_after(self(), :deadline_passed, 300)
    assert_receive :deadline_passed, 1_000
    :ok = :sys.resume(runner)
    assert {:error, :mcp_connection_timed_out} = Task.await(caller)
  end
end
