defmodule Vxpipe.MCP.DiscoveryIOTest do
  use ExUnit.Case, async: true
  alias Vxpipe.MCP.DiscoveryIO

  test "owner death stops in-flight IO even when the metadata worker is separate" do
    tasks = start_supervised!({Task.Supervisor, name: nil})

    owner =
      Task.Supervisor.async_nolink(tasks, fn ->
        receive do
          :stop -> :ok
        end
      end)

    test = self()

    worker =
      Task.Supervisor.async_nolink(tasks, fn ->
        DiscoveryIO.run(owner.pid, fn ->
          send(test, {:io, self()})

          receive do
            :never -> :ok
          end
        end)
      end)

    assert_receive {:io, io}, 1_000
    ref = Process.monitor(io)
    Task.shutdown(owner, :brutal_kill)
    assert_receive {:DOWN, ^ref, :process, ^io, _}, 1_000
    Task.shutdown(worker, :brutal_kill)
  end

  test "successful IO returns its value" do
    assert {:ok, :document} = DiscoveryIO.run(self(), fn -> {:ok, :document} end)
  end

  test "callback exceptions and throws return fixed failures without reporting their contents" do
    tasks = start_supervised!({Task.Supervisor, name: nil})
    marker = "synthetic-discovery-secret-marker"
    owner = self()

    for operation <- [fn -> raise marker end, fn -> throw(marker) end, fn -> exit(marker) end] do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          task = Task.Supervisor.async_nolink(tasks, fn -> DiscoveryIO.run(owner, operation) end)
          assert {:ok, {:error, :discovery_io_failed}} = Task.yield(task, 1_000)
        end)

      refute log =~ marker
    end
  end
end
