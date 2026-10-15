defmodule Vxpipe.Gateway.Integration.ManagedMediaCleanupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor, TestTelephonyLeg}
  alias Vxpipe.Gateway.Telephony.MediaBinding

  @moduletag :integration

  for provider <- [:telnyx, :twilio], stop <- [:room, :tracker] do
    @tag provider: provider, stop: stop
    test "#{provider} actual WebSocket owner closes after #{stop} termination", c do
      {:ok, command} =
        CallEngine.Command.CreateRoom.new(
          tenant_id: "managed-socket-tenant",
          actor_id: "socket-test",
          deadline: DateTime.add(DateTime.utc_now(), 60, :second)
        )

      {:ok, room} = CallEngine.create_room(command)

      cleanup = %{
        tenant_key: room.tenant_id,
        call_id: "socket-call",
        room_id: room.room_id,
        incarnation_id: room.incarnation_id
      }

      {:ok, tracker} = CallCleanupSupervisor.start_new(cleanup)

      on_exit(fn ->
        CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)

        case CallCleanupSupervisor.lookup(cleanup) do
          {:ok, owner} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, owner)
          {:error, :not_found} -> :ok
        end
      end)

      leg = start_supervised!({TestTelephonyLeg, observer: self()})

      binding =
        %MediaBinding{
          provider: c.provider,
          service_id: "socket-service",
          ingress_key: "socket-ingress",
          tenant_id: room.tenant_id,
          call_id: cleanup.call_id,
          room_id: room.room_id,
          incarnation_id: room.incarnation_id,
          participant_id: "socket-participant",
          provider_connection_id: "socket-provider-connection",
          provider_call_control_id: "socket-control",
          provider_call_leg_id: "socket-leg",
          provider_call_session_id: nil,
          client_state_leg_id: "socket-local-leg",
          leg: leg
        }
        |> Map.put(:cleanup_binding, cleanup)

      module =
        case c.provider do
          :telnyx -> Vxpipe.Providers.Telnyx.TelephonyMediaSocket
          :twilio -> Vxpipe.Providers.Twilio.TelephonyMediaSocket
        end

      plug = fn conn, _ ->
        if Plug.Conn.get_req_header(conn, "upgrade") == ["websocket"] do
          conn
          |> WebSockAdapter.upgrade(module, %{binding: binding, clock: fn -> 0 end}, [])
          |> Plug.Conn.halt()
        else
          Plug.Conn.send_resp(conn, 404, "not found")
        end
      end

      server =
        start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0, startup_log: false})

      {:ok, {_, port}} = ThousandIsland.listener_info(server)
      socket = connect(port)
      on_exit(fn -> :gen_tcp.close(socket) end)
      # A pong proves that the production WebSock init completed, not merely HTTP upgrade.
      :ok = :gen_tcp.send(socket, <<0x89, 0x80, 0, 0, 0, 0>>)
      assert {:ok, <<0x8A, 0>>} = :gen_tcp.recv(socket, 2, 2_000)
      assert %{resources: resources} = CallCleanup.snapshot(tracker)
      assert [owner] = Map.keys(resources)

      assert %{kind: :telephony_socket, owner: ^owner, acknowledgement: :complete} =
               resources[owner]

      refute owner == self()
      monitor = Process.monitor(owner)
      {:ok, _} = CallCleanup.observe(tracker)

      case c.stop do
        :room ->
          assert :ok = CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)

        :tracker ->
          assert :ok = DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
      end

      assert {:ok, <<0x88, length>>} = :gen_tcp.recv(socket, 2, 2_000)
      assert {:ok, <<1000::16, _reason::binary>>} = :gen_tcp.recv(socket, length, 2_000)
      :ok = :gen_tcp.send(socket, <<0x88, 0x82, 0, 0, 0, 0, 1000::16>>)
      assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :local_closed}}, 2_000

      if c.stop == :room do
        assert_receive {:call_cleanup_changed, ^tracker, %{status: :complete}}, 2_000
      else
        assert {:error, :not_found} = CallCleanupSupervisor.lookup(cleanup)
      end
    end
  end

  defp connect(port) do
    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, packet: :http_bin], 2_000)

    key = Base.encode64(:crypto.strong_rand_bytes(16))

    :ok =
      :gen_tcp.send(socket, [
        "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n",
        "Connection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ",
        key,
        "\r\n\r\n"
      ])

    assert {:ok, {:http_response, _, 101, _}} = :gen_tcp.recv(socket, 0, 2_000)
    headers(socket)
    :ok = :inet.setopts(socket, packet: :raw)
    socket
  end

  defp headers(socket) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, :http_eoh} -> :ok
      {:ok, {:http_header, _, _, _, _}} -> headers(socket)
    end
  end
end
