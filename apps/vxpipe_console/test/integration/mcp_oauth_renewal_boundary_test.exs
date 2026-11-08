defmodule Vxpipe.Console.MCPOAuthRenewalBoundaryTest do
  use Vxpipe.Console.Test.OutboundMCPOAuthCase, async: false
  alias Vxpipe.Calls.{Administration, MCPOAuthRefresh, MCPRuntimeCredentials}
  alias Vxpipe.MCP.PreflightRunner

  setup data do
    handoff = start(data)
    assert_connected(data, authorize(data, handoff))
    id = handoff["connection_id"]
    %{id: id, before: resolve(data, id)}
  end

  test "retiring a session cancels its held renewal before close and leaves the claim fenced",
       data do
    connection = session(data)
    independent = session(data)
    runner = runner(timeout: 5_000)

    options =
      renewal_options(data, runner, :hold)
      |> Keyword.put(:mcp_session, Vxpipe.MCP.Connection.owner(connection))

    observer = self()
    start_supervised!({Task, fn -> send(observer, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000
    monitor = Process.monitor(worker)
    :ok = :sys.suspend(runner)

    try do
      assert :ok = Vxpipe.MCP.Connections.close(connection)
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 500
      assert_receive {:renewed, {:error, :oauth_reconnect_required}}, 1_000
      send(worker, :release)
      assert_fenced(data, options)

      assert {:ok, %{connection_status: :ready}} =
               Vxpipe.MCP.ReadyClientRuntime.status(Vxpipe.MCP.Connection.client(independent))

      assert resolve(data, data.id).connection.status == "connected"
    after
      :sys.resume(runner)
    end
  end

  test "closing a nonclaimant session preserves the other session's renewal", data do
    connection = session(data)
    independent = session(data)
    runner = runner(limit: 2, timeout: 5_000)

    options =
      renewal_options(data, runner, :hold)
      |> Keyword.put(:mcp_session, Vxpipe.MCP.Connection.owner(connection))

    observer = self()
    start_supervised!({Task, fn -> send(observer, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000

    contender = Keyword.put(options, :mcp_session, Vxpipe.MCP.Connection.owner(independent))
    assert {:error, :oauth_refresh_in_progress} = refresh(data, contender)
    refute_received {:token_request, _}
    assert :ok = Vxpipe.MCP.Connections.close(independent)
    send(worker, :release)
    assert_receive {:renewed, :ok}, 1_000
    assert resolve(data, data.id).secrets["access_token"] == "renewed-access"

    assert {:ok, %{connection_status: :ready}} =
             Vxpipe.MCP.ReadyClientRuntime.status(Vxpipe.MCP.Connection.client(connection))
  end

  test "zero capacity leaves durable grant and revision untouched", data do
    options = renewal_options(data, runner(limit: 0))
    assert {:error, :mcp_connection_busy} = refresh(data, options)
    assert resolve(data, data.id) == data.before
    refute_received {:token_request, _}
  end

  test "one held renewal rejects another tenant before its durable claim", data do
    runner = runner(limit: 1, timeout: 5_000)
    options = renewal_options(data, runner, :hold)
    owner = self()
    start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000

    {:ok, tenant, _} = Administration.bootstrap_tenant("Other renewal", [:admin], data.options)
    id = Vxpipe.Calls.PublicId.uuid()

    assert {:ok, _} =
             ConnectionStore.create_oauth(
               data.context,
               tenant.key,
               id,
               data.before.connection,
               data.before.secrets
             )

    assert {:error, :mcp_connection_busy} =
             MCPOAuthRefresh.refresh(tenant.key, id, 1, 1, renewal_options(data, runner))

    assert {:ok, unchanged} = ConnectionStore.resolve(data.context, tenant.key, id)
    assert unchanged.secrets == data.before.secrets
    refute_received {:token_request, _}
    send(worker, :release)
    assert_receive {:renewed, :ok}, 1_000
    assert resolve(data, data.id).secrets["access_token"] == "renewed-access"
  end

  for cause <- [:timeout, :caller_death] do
    @tag cause: cause
    test "#{cause} cancels token work and leaves a fenced grant", data do
      cause = data.cause
      runner = runner(timeout: Map.fetch!(%{timeout: 200, caller_death: 5_000}, cause))
      options = renewal_options(data, runner, :hold)
      owner = self()

      caller =
        start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})

      assert_receive {:token_request, worker}, 1_000
      monitor = Process.monitor(worker)

      case cause do
        :timeout ->
          assert_receive {:renewed, {:error, :mcp_connection_timed_out}}, 1_000

        :caller_death ->
          caller_monitor = Process.monitor(caller)
          stop_supervised!(Task)
          assert_receive {:DOWN, ^caller_monitor, :process, ^caller, _}, 1_000
      end

      assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
      assert_fenced(data, options)
    end
  end

  test "a queued successful token response after the deadline cannot rotate storage", data do
    runner = runner(timeout: 750)
    options = renewal_options(data, runner, :hold)
    owner = self()
    start_supervised!({Task, fn -> send(owner, {:renewed, refresh(data, options)}) end})
    assert_receive {:token_request, worker}, 1_000
    %{jobs: jobs} = :sys.get_state(runner)
    [%{task: %{pid: completion}}] = Map.values(jobs)
    monitor = Process.monitor(completion)
    :ok = :sys.suspend(runner)
    send(worker, :release)
    assert_receive {:DOWN, ^monitor, :process, ^completion, :normal}, 1_000
    Process.send_after(self(), :deadline_passed, 800)
    assert_receive :deadline_passed, 2_000
    :ok = :sys.resume(runner)
    assert_receive {:renewed, {:error, :mcp_connection_timed_out}}, 1_000
    assert_fenced(data, options)
  end

  defp session(data) do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {__MODULE__, make_ref()}}}

    host =
      start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name}, id: make_ref())

    {:ok, key} =
      Vxpipe.MCP.ConnectionKey.new(
        scope: :tenant,
        tenant_id: data.tenant,
        integration_id: data.id,
        credential_generation: "1"
      )

    {:ok, connection} =
      Vxpipe.MCP.Connections.open(
        key,
        [endpoint: data.before.connection.endpoint],
        owner: host,
        runtime: Vxpipe.MCP.ReadyClientRuntime
      )

    connection
  end

  defp assert_fenced(data, options) do
    current = resolve(data, data.id)
    assert current.secrets["access_token"] == data.before.secrets["access_token"]
    assert current.secrets["grant_revision"] == data.before.secrets["grant_revision"]
    assert is_map(current.secrets["refresh_claim"])
    deadline = current.secrets["refresh_claim"]["deadline"]
    expired = Keyword.put(options, :now, fn -> DateTime.from_unix!(deadline) end)

    assert {:error, :oauth_reconnect_required} =
             MCPRuntimeCredentials.resolve(data.tenant, data.id, 1, expired)

    refute_received {:token_request, _}
  end

  defp runner(settings) do
    tasks = start_supervised!({Task.Supervisor, name: nil}, id: :renewal_tasks)

    start_supervised!(
      {PreflightRunner, [name: nil, task_supervisor: tasks, interval: 0] ++ settings},
      id: :renewal_runner
    )
  end

  defp renewal_options(data, runner, mode \\ :immediate) do
    owner = self()

    protocol =
      data.protocol
      |> Keyword.put(:renewal_runner, runner)
      |> Keyword.put(:request_fun, fn _, _, _, _ ->
        send(owner, {:token_request, self()})

        if mode == :hold do
          receive do
            :release -> :ok
          end
        end

        {:ok,
         {{~c"HTTP/1.1", 200, ~c"OK"}, [],
          JSON.encode!(%{
            "access_token" => "renewed-access",
            "refresh_token" => "rotated-refresh",
            "expires_in" => 300,
            "token_type" => "Bearer"
          })}}
      end)

    Keyword.put(data.options, :mcp_oauth_refresh, {Vxpipe.Calls.MCPOAuthProtocol, protocol})
  end

  defp refresh(data, options),
    do: MCPOAuthRefresh.refresh(data.tenant, data.id, 1, 1, options)
end
