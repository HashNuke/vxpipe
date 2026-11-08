defmodule Vxpipe.MCP.SessionRetirementTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    Connection,
    ConnectionKey,
    Connections,
    ExMCPClient,
    RuntimeAuthProvider,
    SessionHTTPFixture,
    SessionLifecycle
  }

  alias Vxpipe.MCP.Test.RuntimeAuthFixture

  @moduletag :integration
  @moduletag :capture_log
  @moduletag timeout: 15_000

  test "retirement fences a POST held after authorization before final submission" do
    observer = self()
    mode = start_supervised!({Agent, fn -> :ready end})

    resolver = fn _, _ ->
      if Agent.get(mode, & &1) == :hold do
        send(observer, {:dns_held, self()})
        receive do: (:release -> :ok)
      end

      {:ok, [{127, 0, 0, 1}]}
    end

    {connection, _server} = open_session(runtime_options: [dns_resolver: resolver])
    Agent.update(mode, fn _ -> :hold end)

    start_supervised!(
      {Task,
       fn ->
         send(
           observer,
           {:tool_result,
            ExMCPClient.call_tool(Connection.client(connection), "hold", %{}, 5_000)}
         )
       end}
    )

    assert_receive {:dns_held, worker}, 1_000

    assert {:ok, _permission} =
             SessionLifecycle.begin_close(
               Connection.owner(connection),
               Connection.client(connection),
               self(),
               now() + 3_000
             )

    assert :error =
             Connections.lookup(Connection.key(connection),
               owner: Connection.session_owner(connection)
             )

    Agent.update(mode, fn _ -> :ready end)
    send(worker, :release)
    assert_receive {:tool_result, {:error, :not_submitted}}, 1_000
    refute_received {:session_http_held, :post, _}
    assert :ok = Connections.close(connection)
  end

  test "one absolute deadline bounds held DELETE and blocked cleanup authorization across sessions" do
    observer = self()

    blocked = fn ->
      send(observer, {:cleanup_held, self()})
      receive do: (:release -> {:ok, %{auth_method: "none", headers: []}})
    end

    {first, _} = open_session(server_options: [hold_delete: true])
    {second, _} = open_session(cleanup: blocked)
    monitors = monitors([first, second])
    started = now()
    assert :ok = Connections.close_all([first, second], deadline: started + 350)
    assert now() - started < 800
    assert_received {:session_http_held, :delete, _}
    assert_received {:cleanup_held, _}
    assert_terminated(monitors)
    assert_receive {:session_http_closed, :delete, {:error, :closed}}, 1_000
    for _ <- 1..2, do: assert_receive({:session_http_closed, :get, {:error, :closed}}, 1_000)
  end

  test "closing rejects new tool authorization and only admits the exact cleanup permission once" do
    observer = self()
    count = start_supervised!({Agent, fn -> 0 end})

    current = fn ->
      Agent.update(count, &(&1 + 1))
      {:ok, %{auth_method: "none", headers: []}}
    end

    {connection, _} = open_session(request: current)
    before = Agent.get(count, & &1)
    client = Connection.client(connection)

    assert {:ok, permission} =
             SessionLifecycle.begin_close(
               Connection.owner(connection),
               client,
               observer,
               now() + 3_000
             )

    assert {:error, :not_submitted} = ExMCPClient.call_tool(client, "hold", %{}, 500)
    assert Agent.get(count, & &1) == before
    assert :ok = ExMCP.Client.disconnect(client, make_ref(), 500)
    refute_received :session_http_delete
    assert :ok = ExMCP.Client.disconnect(client, permission, 500)
    assert_receive :session_http_delete
    assert :ok = ExMCP.Client.disconnect(client, permission, 500)
    refute_received :session_http_delete
    assert :ok = Connections.close(connection)
  end

  test "every selected session is fenced before the first cleanup callback" do
    observer = self()
    {second, _} = open_session(server_options: [hold_delete: true])

    cleanup = fn ->
      result = SessionLifecycle.admit(Connection.owner(second), :post, :prepare, nil)
      send(observer, {:other_admission, result})
      {:ok, %{auth_method: "none", headers: []}}
    end

    {first, _} = open_session(cleanup: cleanup)
    assert :ok = Connections.close_all([first, second], deadline: now() + 200)
    assert_received {:other_admission, {:error, :session_retired}}
  end

  test "an unrelated owner stays callable while cleanup is blocked" do
    observer = self()
    {closing, _} = open_session(server_options: [hold_delete: true])
    {other, _} = open_session()

    start_supervised!(
      {Task,
       fn ->
         send(observer, {:closed, Connections.close_all([closing], deadline: now() + 400)})
       end}
    )

    assert_receive {:session_http_held, :delete, _}, 1_000

    assert {:ok, %{"content" => [%{"text" => session}]}} =
             ExMCPClient.call_tool(Connection.client(other), "echo", %{}, 200)

    assert {:ok, %{"content" => [%{"text" => ^session}]}} =
             ExMCPClient.call_tool(Connection.client(other), "echo", %{}, 200)

    assert_receive {:closed, :ok}, 1_000
    assert Connections.owned_by?(other, Connection.session_owner(other))
  end

  test "close acknowledges the stream socket and admitted POST termination" do
    observer = self()
    {connection, _} = open_session()
    client = Connection.client(connection)
    state = :sys.get_state(client)
    stream = :sys.get_state(state.transport_state.sse_pid).ref
    transport = transport(connection)

    assert Enum.any?(DynamicSupervisor.which_children(transport), fn {_, pid, _, _} ->
             pid == stream
           end)

    start_supervised!(
      {Task,
       fn ->
         send(observer, {:tool_result, ExMCPClient.call_tool(client, "hold", %{}, 5_000)})
       end}
    )

    assert_receive {:session_http_held, :post, _}, 1_000
    all = monitors([connection])
    assert :ok = Connections.close(connection)
    assert_terminated(all)
    assert_receive {:session_http_closed, :get, {:error, :closed}}, 1_000
    assert_receive {:session_http_closed, :post, {:error, :closed}}, 1_000
  end

  test "close still drains transport after the client has died" do
    {connection, _} = open_session()
    integration = Connection.owner(connection)
    client = Connection.client(connection)
    all = monitors([connection])
    :ok = :sys.suspend(integration)
    client_ref = Process.monitor(client)
    Process.exit(client, :kill)
    assert_receive {:DOWN, ^client_ref, :process, ^client, :killed}

    try do
      assert :ok = Connections.close(connection)
      assert_terminated(all)
    after
      Process.exit(integration, :kill)
    end
  end

  test "unresponsive lifecycle guards share the batch deadline while fencing" do
    connections =
      for _ <- 1..3 do
        {connection, _} = open_session()
        :ok = :sys.suspend(GenServer.whereis(SessionLifecycle.name(Connection.owner(connection))))
        connection
      end

    started = now()
    assert :ok = Connections.close_all(connections, deadline: started + 30)
    assert now() - started < 250
  end

  test "close waits for a surviving transport subtree after integration death" do
    observer = self()
    {connection, _} = open_session()
    transport = transport(connection)
    integration = Connection.owner(connection)

    child =
      Supervisor.child_spec(
        {Task,
         fn ->
           Process.flag(:trap_exit, true)
           send(observer, {:slow_child, self()})
           receive do: (:release -> :ok)
         end},
        restart: :temporary,
        shutdown: 1_000
      )

    {:ok, slow} = DynamicSupervisor.start_child(transport, child)
    assert_receive {:slow_child, ^slow}
    all = monitors([connection])
    ref = Process.monitor(integration)
    Process.exit(integration, :kill)
    assert_receive {:DOWN, ^ref, :process, ^integration, :killed}
    registry_key = {:owner, Connection.session_owner(connection), Connection.key(connection)}

    for {_, partition, _, _} <- Supervisor.which_children(Vxpipe.MCP.ConnectionRegistry),
        do: :sys.get_state(partition)

    assert Registry.lookup(Vxpipe.MCP.ConnectionRegistry, registry_key) == []

    start_supervised!(
      {Task, fn -> send(observer, {:late_close_done, Connections.close(connection)}) end}
    )

    try do
      refute_receive {:late_close_done, _}, 100
    after
      send(slow, :release)
    end

    assert_receive {:late_close_done, :ok}, 1_000
    assert_terminated(all)
  end

  for cause <- [:caller, :client, :host] do
    @cause cause
    test "#{cause} death during cleanup removes every local worker" do
      observer = self()

      blocked = fn ->
        send(observer, {:cleanup_held, self()})
        receive do: (:release -> {:ok, %{auth_method: "none", headers: []}})
      end

      {connection, _} = open_session(cleanup: blocked)
      all = monitors([connection])

      closer =
        start_supervised!(
          {Task, fn -> Connections.close_all([connection], deadline: now() + 5_000) end}
        )

      assert_receive {:cleanup_held, _}, 1_000

      pid =
        case @cause do
          :caller -> closer
          :client -> Connection.client(connection)
          :host -> Connection.session_owner(connection)
        end

      Process.exit(pid, :kill)
      for {worker, ref} <- all, do: assert_receive({:DOWN, ^ref, :process, ^worker, _}, 1_000)
    end
  end

  defp open_session(opts \\ []) do
    observer = self()

    server =
      start_supervised!(
        {SessionHTTPFixture, [owner: observer] ++ Keyword.get(opts, :server_options, [])}
      )

    owner =
      start_supervised!(
        {DynamicSupervisor,
         strategy: :one_for_one,
         name: {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:retirement_host, make_ref()}}}},
        id: make_ref()
      )

    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "retirement-fixture",
        integration_id: "retirement-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    current = {:ok, %{auth_method: "none", headers: []}}

    {:ok, auth} =
      RuntimeAuthProvider.init(%{
        tenant: "retirement-fixture",
        connection_id: key.integration_id,
        generation: 1,
        auth_method: "none",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {RuntimeAuthFixture,
           {observer,
            %{
              request: Keyword.get(opts, :request, current),
              cleanup: Keyword.get(opts, :cleanup, current)
            }}}
      })

    {:ok, connection} =
      Connections.open_loopback_test(
        key,
        [endpoint: SessionHTTPFixture.endpoint(server), runtime_authentication: auth],
        owner: owner,
        runtime_options: Keyword.get(opts, :runtime_options, [])
      )

    assert_receive :session_http_initialized, 1_000
    assert_receive {:session_http_held, :get, _}, 1_000
    {connection, server}
  end

  defp transport(connection) do
    [{pid, _}] =
      Registry.lookup(
        Vxpipe.MCP.ConnectionRegistry,
        {:transport_workers, Connection.owner(connection)}
      )

    pid
  end

  defp monitors(connections) do
    connections
    |> Enum.flat_map(fn c ->
      [Connection.owner(c), transport(c) | descendants(Connection.owner(c))]
    end)
    |> Enum.uniq()
    |> Map.new(&{&1, Process.monitor(&1)})
  end

  defp descendants(supervisor) do
    Enum.flat_map(Supervisor.which_children(supervisor), fn
      {_, pid, :supervisor, _} when is_pid(pid) -> [pid | descendants(pid)]
      {_, pid, :worker, _} when is_pid(pid) -> [pid]
      _ -> []
    end)
  end

  defp assert_terminated(monitors) do
    for {pid, ref} <- monitors do
      assert_received {:DOWN, ^ref, :process, ^pid, _}
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
