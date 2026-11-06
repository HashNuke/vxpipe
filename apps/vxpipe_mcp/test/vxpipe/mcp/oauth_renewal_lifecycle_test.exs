defmodule Vxpipe.MCP.OAuthRenewalLifecycleTest do
  use ExUnit.Case, async: false
  alias Vxpipe.MCP.{DiscoveryIO, OAuthRenewalSupervisor, PreflightRunner}

  test "restarting the registered renewal runner retires owned work and accepts fresh work" do
    owner = self()
    callers = start_supervised!({Task.Supervisor, name: nil})
    runner = Process.whereis(Vxpipe.MCP.OAuthRenewalRunner)
    tasks = Process.whereis(Vxpipe.MCP.OAuthRenewalTasks)

    caller =
      Task.Supervisor.async_nolink(callers, fn ->
        try do
          PreflightRunner.run(runner, "tenant", fn ->
            send(owner, {:renewal, self()})

            DiscoveryIO.run(self(), fn ->
              send(owner, {:io, self()})

              receive do
                :never -> {:ok, :unused}
              end
            end)
          end)
        catch
          :exit, _ -> {:error, :runner_stopped}
        end
      end)

    assert_receive {:renewal, renewal}
    assert_receive {:io, io}
    refs = for pid <- [runner, tasks, renewal, io], do: {Process.monitor(pid), pid}
    Process.exit(runner, :kill)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    assert {:error, :runner_stopped} = Task.await(caller)

    children = Supervisor.which_children(OAuthRenewalSupervisor)
    assert {PreflightRunner, replacement, :worker, _} = List.keyfind(children, PreflightRunner, 0)
    refute replacement == runner
    assert Process.whereis(Vxpipe.MCP.OAuthRenewalRunner) == replacement

    assert {:ok, :recovered} =
             PreflightRunner.run(replacement, "tenant", fn -> {:ok, :recovered} end)
  end
end
