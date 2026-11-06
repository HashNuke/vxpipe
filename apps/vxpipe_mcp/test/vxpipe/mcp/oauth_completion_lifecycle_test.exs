defmodule Vxpipe.MCP.OAuthCompletionLifecycleTest do
  use ExUnit.Case, async: false
  alias Vxpipe.MCP.{DiscoveryIO, OAuthCompletionSupervisor, PreflightRunner}

  test "restarting the registered completion runner retires owned work and accepts fresh work" do
    owner = self()
    callers = start_supervised!({Task.Supervisor, name: nil})
    runner = Process.whereis(Vxpipe.MCP.OAuthCompletionRunner)
    tasks = Process.whereis(Vxpipe.MCP.OAuthCompletionTasks)

    caller =
      Task.Supervisor.async_nolink(callers, fn ->
        try do
          PreflightRunner.run(runner, "tenant", fn ->
            send(owner, {:completion, self()})

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

    assert_receive {:completion, completion}
    assert_receive {:io, io}
    refs = for pid <- [runner, tasks, completion, io], do: {Process.monitor(pid), pid}
    Process.exit(runner, :kill)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 1_000)
    assert {:error, :runner_stopped} = Task.await(caller)

    children = Supervisor.which_children(OAuthCompletionSupervisor)
    assert {PreflightRunner, replacement, :worker, _} = List.keyfind(children, PreflightRunner, 0)
    refute replacement == runner
    assert Process.whereis(Vxpipe.MCP.OAuthCompletionRunner) == replacement

    assert {:ok, :recovered} =
             PreflightRunner.run(replacement, "tenant", fn -> {:ok, :recovered} end)
  end
end
