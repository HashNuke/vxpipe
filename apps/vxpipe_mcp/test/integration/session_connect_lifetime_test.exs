defmodule Vxpipe.MCP.SessionConnectLifetimeTest do
  use ExUnit.Case, async: false

  alias Vxpipe.MCP.{Connection, ConnectionKey, ConnectionNames, Connections, SessionTLSFixture}

  @moduletag :integration
  @moduletag :capture_log

  for cancellation <- [:session_close, :host_stop, :host_death, :client_death] do
    @cancellation cancellation

    test "#{cancellation} closes an established session's stalled GET connection" do
      observer = self()
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_address, port}} = :inet.sockname(listener)
      on_exit(fn -> :gen_tcp.close(listener) end)

      fixture =
        start_supervised!(
          {Task, fn -> SessionTLSFixture.initialize_then_hold_get(listener, observer) end}
        )

      name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:get_connect_host, make_ref()}}}

      host =
        start_supervised!(
          Supervisor.child_spec({DynamicSupervisor, strategy: :one_for_one, name: name},
            restart: :temporary
          ),
          id: :get_host
        )

      {:ok, key} =
        ConnectionKey.new(
          scope: :application,
          integration_id: "get-connect-#{System.unique_integer([:positive])}",
          credential_generation: "1"
        )

      assert {:ok, connection} =
               Connections.open_loopback_test(
                 key,
                 [endpoint: "http://127.0.0.1:#{port}/mcp"],
                 owner: host,
                 runtime_options: [
                   url: "https://127.0.0.1:#{port}/mcp",
                   security: %{
                     trusted_origins: ["https://127.0.0.1:#{port}"],
                     tls: %{verify: :verify_none}
                   }
                 ]
               )

      assert_receive :tls_session_initialized, 2_000
      send(fixture, :stall_get)
      assert_receive :get_tls_connect_blocked, 2_000
      integration = Connection.owner(connection)

      [{transport, _}] =
        Registry.lookup(Vxpipe.MCP.ConnectionRegistry, {:transport_workers, integration})

      monitors =
        Map.new(
          [integration, Connection.client(connection), transport],
          &{&1, Process.monitor(&1)}
        )

      case @cancellation do
        :session_close ->
          assert :ok =
                   Connections.close_all([connection],
                     deadline: System.monotonic_time(:millisecond) + 200
                   )

        :host_stop ->
          stop_supervised(:get_host)

        :host_death ->
          Process.exit(host, :kill)

        :client_death ->
          Process.exit(Connection.client(connection), :kill)
      end

      for {pid, ref} <- monitors do
        assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
      end

      assert_receive {:get_tls_peer_closed, {:error, :closed}}, 1_000
    end
  end

  for cancellation <- [:deadline, :caller_death, :host_stop, :revoke] do
    @cancellation cancellation

    test "#{cancellation} closes a socket stalled during TLS connection" do
      observer = self()
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_address, port}} = :inet.sockname(listener)
      on_exit(fn -> :gen_tcp.close(listener) end)

      start_supervised!(
        {Task,
         fn ->
           {:ok, peer} = :gen_tcp.accept(listener)
           {:ok, <<22, _client_hello::binary>>} = :gen_tcp.recv(peer, 0, 2_000)
           send(observer, :tls_connect_blocked)
           send(observer, {:tls_peer_closed, await_peer_close(peer)})
         end}
      )

      name = {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:connect_host, make_ref()}}}
      host = start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: name}, id: :host)

      {:ok, key} =
        ConnectionKey.new(
          scope: :application,
          integration_id: "connect-#{System.unique_integer([:positive])}",
          credential_generation: "1"
        )

      opts = [owner: host]
      timeout = if @cancellation == :deadline, do: 500, else: 5_000

      caller =
        start_supervised!(
          {Task,
           fn ->
             result =
               Connections.open_loopback_test(
                 key,
                 [endpoint: "http://127.0.0.1:#{port}/mcp"],
                 Keyword.merge(opts,
                   deadline: System.monotonic_time(:millisecond) + timeout,
                   # Use the isolated fixture profile with TLS on the actual wire.
                   runtime_options: [
                     url: "https://127.0.0.1:#{port}/mcp",
                     security: %{trusted_origins: ["https://127.0.0.1:#{port}"]}
                   ]
                 )
               )

             send(observer, {:connect_result, result})
           end},
          id: :caller
        )

      try do
        assert_receive :tls_connect_blocked, 2_000
        {:ok, integration} = ConnectionNames.lookup(:owner, key, Keyword.get(opts, :owner))
        monitor = Process.monitor(integration)

        case @cancellation do
          :deadline -> :ok
          :caller_death -> Process.exit(caller, :kill)
          :host_stop -> stop_supervised(:host)
          :revoke -> assert :ok = Connections.revoke(key)
        end

        assert_receive {:DOWN, ^monitor, :process, ^integration, _reason}, 1_000
        assert_receive {:tls_peer_closed, {:error, :closed}}, 1_000
        refute_receive {:connect_result, {:ok, _late_handle}}, 20
      after
        Process.exit(caller, :kill)
      end
    end
  end

  defp await_peer_close(peer, deadline \\ System.monotonic_time(:millisecond) + 5_000) do
    timeout = max(deadline - System.monotonic_time(:millisecond), 0)

    case :gen_tcp.recv(peer, 0, timeout) do
      # Drain TLS cancellation/close alerts, which can occupy separate packets.
      {:ok, _alert_bytes} -> await_peer_close(peer, deadline)
      closed -> closed
    end
  end
end
