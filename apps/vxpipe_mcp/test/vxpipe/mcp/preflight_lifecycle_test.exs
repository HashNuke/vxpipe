defmodule Vxpipe.MCP.PreflightLifecycleTest do
  use ExUnit.Case, async: false
  alias Vxpipe.MCP.{Preflight, PreflightRunner, PreflightSupervisor}

  @input %{"endpoint" => "https://mcp.example.test/mcp", "revision" => "draft"}

  setup do
    callers = start_supervised!({Task.Supervisor, name: nil})
    %{callers: callers}
  end

  for phase <- [:dns, :http], cause <- [:timeout, :caller_death] do
    test "#{cause} retires composed #{phase} work", %{callers: callers} do
      phase = unquote(phase)
      tasks = start_supervised!({Task.Supervisor, name: nil}, id: :discovery_tasks)

      runner =
        start_supervised!(
          {PreflightRunner,
           name: nil,
           task_supervisor: tasks,
           timeout: unquote(if(cause == :timeout, do: 200, else: 5_000))}
        )

      caller = start_probe(callers, runner, phase)
      assert_receive {:preflight, probe}
      assert_receive {:io, io}
      probe_ref = Process.monitor(probe)
      io_ref = Process.monitor(io)

      stop_probe(caller, unquote(cause))

      assert_receive {:DOWN, ^probe_ref, :process, ^probe, _}, 1_000
      assert_receive {:DOWN, ^io_ref, :process, ^io, _}, 1_000
      assert %{jobs: jobs} = :sys.get_state(runner)
      assert jobs == %{}
      assert Task.Supervisor.children(tasks) == []
    end
  end

  test "restarting the application runner retires its task supervisor and nested IO", %{
    callers: callers
  } do
    runner = Process.whereis(PreflightRunner)
    tasks = Process.whereis(Vxpipe.MCP.PreflightTasks)
    caller = start_probe(callers, runner, :http)
    assert_receive {:preflight, probe}
    assert_receive {:io, io}
    refs = for pid <- [runner, tasks, probe, io], do: {Process.monitor(pid), pid}

    Process.exit(runner, :kill)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    assert {:error, :runner_stopped} = Task.await(caller)

    children = Supervisor.which_children(PreflightSupervisor)
    assert {PreflightRunner, replacement, :worker, _} = List.keyfind(children, PreflightRunner, 0)
    refute replacement == runner

    assert {:ok, :recovered} =
             PreflightRunner.run(replacement, "recovery", fn -> {:ok, :recovered} end)
  end

  defp stop_probe(caller, :timeout),
    do: assert({:error, :mcp_connection_timed_out} = Task.await(caller, 2_000))

  defp stop_probe(caller, :caller_death), do: Task.shutdown(caller, :brutal_kill)

  defp start_probe(callers, runner, phase) do
    owner = self()

    hold = fn ->
      send(owner, {:io, self()})

      receive do
        :never -> {:error, :unexpected}
      end
    end

    options = [
      dns_resolver: fn _, _ ->
        if phase == :dns, do: hold.(), else: {:ok, [{93, 184, 216, 34}]}
      end,
      http_client: fn _, _, _ -> hold.() end
    ]

    Task.Supervisor.async_nolink(callers, fn ->
      try do
        PreflightRunner.run(runner, "tenant", fn ->
          send(owner, {:preflight, self()})
          Preflight.discover("tenant", @input, options)
        end)
      catch
        :exit, _ -> {:error, :runner_stopped}
      end
    end)
  end
end
