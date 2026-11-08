defmodule Vxpipe.Console.MCPOwnedRenewalTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.MCPOAuthRefresh
  alias Vxpipe.MCP.{Connection, ConnectionKey, Connections, PreflightRunner, ReadyClientRuntime}

  setup do
    tasks = start_supervised!({Task.Supervisor, name: nil})

    runner =
      start_supervised!(
        {PreflightRunner, name: nil, task_supervisor: tasks, timeout: 5_000, interval: 0}
      )

    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {__MODULE__, make_ref()}}}
    host = start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name})

    {:ok, key} =
      ConnectionKey.new(
        scope: :application,
        integration_id: "owned-renewal-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    {:ok, connection} =
      Connections.open(key, [endpoint: "https://mcp.example.test/mcp"],
        owner: host,
        runtime: ReadyClientRuntime
      )

    %{
      connection: connection,
      runner: runner,
      tasks: tasks,
      options: [renewal_runner: runner, mcp_session: Connection.owner(connection)]
    }
  end

  test "session close waits for its renewal even when the shared runner is suspended", context do
    %{connection: connection, runner: runner} = context
    start_renewal(context.options)
    assert_receive {:renewal_worker, worker}, 1_000
    monitor = Process.monitor(worker)
    :ok = :sys.suspend(runner)

    try do
      assert :ok = Connections.close(connection)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 200
    after
      :sys.resume(runner)
      send(worker, :finish)
      Connections.close(connection)
    end
  end

  test "the configured renewal deadline still applies while the shared runner is suspended",
       context do
    runner =
      start_supervised!(
        {PreflightRunner, name: nil, task_supervisor: context.tasks, timeout: 150, interval: 0},
        id: :short_runner
      )

    start_renewal(Keyword.put(context.options, :renewal_runner, runner))
    assert_receive {:renewal_worker, worker}, 1_000
    monitor = Process.monitor(worker)
    :ok = :sys.suspend(runner)

    try do
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 500
    after
      :sys.resume(runner)
      send(worker, :finish)
    end
  end

  test "normal runner termination cancels its session worker", context do
    start_renewal(context.options)
    assert_receive {:renewal_worker, worker}, 1_000
    monitor = Process.monitor(worker)
    :ok = GenServer.stop(context.runner, :normal)

    try do
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 500
    after
      send(worker, :finish)
    end
  end

  defp start_renewal(options) do
    observer = self()

    start_supervised!(
      {Task,
       fn ->
         result =
           MCPOAuthRefresh.run(options, "tenant", fn ->
             send(observer, {:renewal_worker, self()})
             receive do: (:finish -> :ok)
           end)

         send(observer, {:renewal_result, result})
       end},
      id: make_ref()
    )
  end
end
