defmodule Vxpipe.Console.IntegrationsDirectory.SupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.IntegrationsDirectory.{Cache, Supervisor, Tasks}

  test "restarting the cache terminates its old fetch workers" do
    owner = self()
    children = Elixir.Supervisor.which_children(Supervisor)
    {Cache, cache, :worker, _} = Enum.find(children, fn {id, _, _, _} -> id == Cache end)

    {:ok, worker} =
      Task.Supervisor.start_child(Tasks, fn ->
        send(owner, {:started, self()})

        receive do
          :release -> :ok
        end
      end)

    on_exit(fn -> Task.Supervisor.terminate_child(Tasks, worker) end)
    assert_receive {:started, ^worker}
    worker_monitor = Process.monitor(worker)
    cache_monitor = Process.monitor(cache)
    Process.exit(cache, :kill)
    assert_receive {:DOWN, ^cache_monitor, :process, ^cache, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :shutdown}, 1000
    _ = :sys.get_state(Supervisor)

    {Cache, replacement, :worker, _} =
      Enum.find(Elixir.Supervisor.which_children(Supervisor), fn {id, _, _, _} -> id == Cache end)

    refute replacement == cache
    _ = :sys.get_state(replacement)
  end
end
