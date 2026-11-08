defmodule Vxpipe.MCP.OwnedPreflightRunnerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, PreflightRunner, ReadyClientRuntime}

  for cause <- [:deadline, :caller_death, :session_close] do
    @tag cause: cause
    test "#{cause} cancels a renewal queued at a suspended admission runner", %{cause: cause} do
      timeout = Map.fetch!(%{deadline: 150, caller_death: 5_000, session_close: 5_000}, cause)
      tasks = start_supervised!({Task.Supervisor, name: nil})

      runner =
        start_supervised!(
          {PreflightRunner, name: nil, task_supervisor: tasks, timeout: timeout, interval: 0}
        )

      host = Vxpipe.MCP.Test.SessionHost.start!()

      {:ok, key} =
        ConnectionKey.new(
          scope: :application,
          integration_id: "queued-renewal-#{System.unique_integer([:positive])}",
          credential_generation: "1"
        )

      {:ok, connection} =
        Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
          owner: host,
          runtime: ReadyClientRuntime
        )

      integration = Connection.owner(connection)

      transport =
        GenServer.whereis(
          {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:transport_workers, integration}}}
        )

      observer = self()
      :ok = :sys.suspend(runner)
      :erlang.trace(transport, true, [:send, :set_on_spawn, {:tracer, observer}])

      caller =
        start_supervised!(
          {Task,
           fn ->
             result =
               PreflightRunner.run_owned(runner, "tenant", integration, fn ->
                 send(observer, :unexpected_callback)
                 :ok
               end)

             send(observer, {:result, result})
           end}
        )

      caller_monitor = Process.monitor(caller)

      try do
        assert_receive {:trace, worker, :send, {:"$gen_call", _, {:permit, "tenant", _entered}},
                        ^runner},
                       1_000

        :erlang.trace(transport, false, [:send, :set_on_spawn])
        monitor = Process.monitor(worker)

        case cause do
          :deadline ->
            assert_receive {:result, {:error, _}}, 500

          :caller_death ->
            Process.exit(caller, :kill)
            assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}

          :session_close ->
            assert :ok = Connections.close(connection)
            assert_received {:DOWN, ^monitor, :process, ^worker, _reason}
            assert_receive {:result, {:error, _}}, 500
        end

        if cause != :session_close,
          do: assert_receive({:DOWN, ^monitor, :process, ^worker, _reason}, 500)

        :ok = :sys.resume(runner)
        _ = :sys.get_state(runner)
        refute_receive :unexpected_callback, 100
      after
        :sys.resume(runner)
        Process.exit(caller, :kill)
        Connections.close(connection)
      end
    end
  end

  test "successful renewal during initialization does not publish the unfinished session" do
    tasks = start_supervised!({Task.Supervisor, name: nil})
    runner = start_supervised!({PreflightRunner, name: nil, task_supervisor: tasks, interval: 0})
    host = Vxpipe.MCP.Test.SessionHost.start!()

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "initializing-renewal-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    observer = self()

    opener =
      start_supervised!(
        {Task,
         fn ->
           Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
             owner: host,
             runtime: Vxpipe.MCP.ControlledStatusRuntime,
             runtime_options: [
               test_status: %{
                 status_callback: fn ->
                   send(observer, :readiness_held)
                   receive do: (:never -> :ok)
                 end
               }
             ]
           )
         end}
      )

    assert_receive :readiness_held, 1_000
    {:ok, integration} = Vxpipe.MCP.ConnectionNames.lookup(:owner, key, host)
    monitor = Process.monitor(integration)
    assert :ok = PreflightRunner.run_owned(runner, "tenant", integration, fn -> :ok end)
    Process.exit(opener, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^integration, _reason}, 500
    assert :error = Connections.lookup(key, owner: host)
  end
end
