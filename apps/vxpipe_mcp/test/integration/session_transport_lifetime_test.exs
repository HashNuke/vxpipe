defmodule Vxpipe.MCP.SessionTransportLifetimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{
    ClientOptions,
    Connection,
    ConnectionKey,
    Connections,
    ExMCPClient,
    RuntimeAuthProvider,
    SessionHTTPFixture
  }

  alias Vxpipe.MCP.Test.RuntimeAuthFixture

  @moduletag :integration
  @moduletag timeout: 15_000

  test "two explicit owners keep independent wire sessions after one owner stops" do
    server = start_supervised!({SessionHTTPFixture, owner: self()})
    first_owner = session_owner(:first_session)
    second_owner = session_owner(:second_session)
    key = connection_key()
    {first, _capture} = open_connection(server, key, owner: first_owner)
    assert_receive {:session_http_session, first_session}
    assert_receive {:session_http_held, :get, _first_peer}, 1_000
    first_workers = session_workers(first)
    {second, _capture} = open_connection(server, key, owner: second_owner)
    assert_receive {:session_http_session, second_session}
    assert_receive {:session_http_held, :get, _second_peer}, 1_000
    refute first_session == second_session
    refute Connection.client(first) == Connection.client(second)
    first_client = Connection.client(first)
    reference = Process.monitor(first_client)

    assert :ok = stop_supervised(:first_session)
    assert_receive {:DOWN, ^reference, :process, ^first_client, :shutdown}

    for {worker, monitor} <- first_workers do
      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
    end

    assert_receive {:session_http_closed, :get, {:error, :closed}}, 1_000

    assert {:ok, %{"content" => [%{"text" => ^second_session}]}} =
             ExMCPClient.call_tool(Connection.client(second), "echo", %{}, 1_000)
  end

  test "an already-dead transport supervisor rejects stateless client startup" do
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    reference = Process.monitor(supervisor)
    assert :ok = stop_supervised(DynamicSupervisor)
    assert_receive {:DOWN, ^reference, :process, ^supervisor, :shutdown}

    server = start_supervised!({SessionHTTPFixture, owner: self(), session: false})

    assert {:ok, options} =
             ClientOptions.build_loopback_test(
               endpoint: SessionHTTPFixture.endpoint(server),
               use_sse: false
             )

    options = Keyword.put(options, :transport_supervisor, supervisor)
    assert {:error, _reason} = start_supervised({ExMCP.Client, options})
  end

  for retirement <- [
        :session_close,
        :client_kill,
        :client_stop,
        :owner_kill,
        :integration_kill,
        :disconnect,
        :receiver_kill
      ] do
    @retirement retirement
    test "#{retirement} terminates held POST work and its active GET stream" do
      server = start_supervised!({SessionHTTPFixture, owner: self()})

      {connection, capture} =
        open_connection(server, connection_key(), owner: session_owner(:wire_host))

      client = Connection.client(connection)
      on_exit(fn -> Connections.close(connection) end)
      assert_receive {:session_http_held, :get, _peer}, 1_000

      linked = retiring_workers(connection, @retirement)

      Agent.update(capture, fn _ -> true end)

      start_supervised!(
        {Task,
         fn ->
           try do
             ExMCPClient.call_tool(client, "hold", %{}, 10_000)
           catch
             :exit, _reason -> :ok
           end
         end}
      )

      assert_receive {:session_authorization, post_worker}, 1_000
      post_ref = Process.monitor(post_worker)

      try do
        assert_receive {:session_http_held, :post, _peer}, 1_000

        retire(@retirement, connection)

        assert_receive {:DOWN, ^post_ref, :process, ^post_worker, _reason}, 1_000

        for {pid, reference} <- linked do
          assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_000
        end

        assert_receive {:session_http_closed, :post, {:error, :closed}}, 1_000
        assert_receive {:session_http_closed, :get, {:error, :closed}}, 1_000
      after
        Enum.each([post_worker | Map.keys(linked)], &Process.exit(&1, :kill))
        Connections.close(connection)
      end
    end
  end

  test "normal client stop terminates an idle GET stream" do
    server = start_supervised!({SessionHTTPFixture, owner: self()})
    {connection, _capture} = open_connection(server)
    on_exit(fn -> Connections.close(connection) end)
    assert_receive {:session_http_held, :get, _peer}, 1_000
    linked = session_workers(connection)

    try do
      assert :ok = ExMCP.Client.stop(Connection.client(connection))

      for {pid, reference} <- linked do
        assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_000
      end

      assert_receive {:session_http_closed, :get, {:error, :closed}}, 1_000
    after
      Enum.each(Map.keys(linked), &Process.exit(&1, :kill))
      Connections.close(connection)
    end
  end

  for {mode, options} <- [stateless: [session: false], get_rejected: [get_status: 405]] do
    @options options
    @mode mode
    test "normal client stop terminates the receiver for #{@mode}" do
      server = start_supervised!({SessionHTTPFixture, [owner: self()] ++ @options})
      {connection, _capture} = open_connection(server)
      on_exit(fn -> Connections.close(connection) end)
      if @mode == :get_rejected, do: assert_receive(:session_http_get_rejected, 1_000)
      linked = session_workers(connection)
      assert map_size(linked) > 0

      try do
        assert :ok = ExMCP.Client.stop(Connection.client(connection))

        for {pid, reference} <- linked do
          assert_receive {:DOWN, ^reference, :process, ^pid, _reason}, 1_000
        end
      after
        Enum.each(Map.keys(linked), &Process.exit(&1, :kill))
        Connections.close(connection)
      end
    end
  end

  defp open_connection(server, key \\ connection_key(), opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :owner, &Vxpipe.MCP.Test.SessionHost.start!/0)
    observer = self()
    capture = start_supervised!({Agent, fn -> false end}, id: make_ref())

    {:ok, authentication} =
      RuntimeAuthProvider.init(%{
        tenant: "session-fixture",
        connection_id: key.integration_id,
        generation: 1,
        auth_method: "none",
        endpoint: "https://mcp.example.test/mcp",
        resolver:
          {RuntimeAuthFixture,
           {observer,
            fn ->
              if Agent.get(capture, & &1), do: send(observer, {:session_authorization, self()})
              {:ok, %{auth_method: "none", headers: []}}
            end}}
      })

    assert {:ok, connection} =
             Connections.open_loopback_test(
               key,
               [
                 endpoint: SessionHTTPFixture.endpoint(server),
                 runtime_authentication: authentication,
                 limits: [stream_handshake_timeout_ms: 500]
               ],
               opts
             )

    assert_receive :session_http_initialized, 1_000

    {connection, capture}
  end

  defp session_owner(id) do
    name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:wire_session_owner, make_ref()}}}
    start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name}, id: id)
  end

  defp session_workers(connection) do
    client = Connection.client(connection)
    owner = Connection.owner(connection)
    {:links, links} = Process.info(client, :links)

    registry_partitions =
      Vxpipe.MCP.ConnectionRegistry
      |> Supervisor.which_children()
      |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)

    (links ++ descendant_workers(owner))
    |> Enum.filter(&(is_pid(&1) and &1 not in [owner, client | registry_partitions]))
    |> Enum.uniq()
    |> Map.new(&{&1, Process.monitor(&1)})
  end

  defp descendant_workers(supervisor) do
    Enum.flat_map(Supervisor.which_children(supervisor), fn
      {_id, pid, :supervisor, _modules} when is_pid(pid) -> descendant_workers(pid)
      {_id, pid, :worker, _modules} when is_pid(pid) -> [pid]
      _terminated -> []
    end)
  end

  defp retiring_workers(connection, retirement)
       when retirement in [:disconnect, :receiver_kill] do
    # These stop transport work while keeping the session/client available.
    # Its disarmed startup guard lives until the integration is retired.
    startup = GenServer.whereis(Vxpipe.MCP.SessionLifecycle.name(Connection.owner(connection)))
    Map.delete(session_workers(connection), startup)
  end

  defp retiring_workers(connection, _retirement), do: session_workers(connection)

  defp retire(:session_close, connection), do: Connections.close(connection)
  defp retire(:client_kill, connection), do: Process.exit(Connection.client(connection), :kill)

  defp retire(:owner_kill, connection),
    do: Process.exit(Connection.session_owner(connection), :kill)

  defp retire(:integration_kill, connection),
    do: Process.exit(Connection.owner(connection), :kill)

  defp retire(:client_stop, connection), do: ExMCP.Client.stop(Connection.client(connection))
  defp retire(:disconnect, connection), do: ExMCP.Client.disconnect(Connection.client(connection))

  defp retire(:receiver_kill, connection) do
    state = :sys.get_state(Connection.client(connection))
    Process.exit(state.receiver_task.pid, :kill)
  end

  defp connection_key do
    {:ok, key} =
      ConnectionKey.new(
        scope: :tenant,
        tenant_id: "session-fixture",
        integration_id: "transport-#{System.unique_integer([:positive])}",
        credential_generation: "1"
      )

    key
  end
end
