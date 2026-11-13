defmodule Vxpipe.Gateway.Integration.ManagedMediaCleanupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.Gateway.{
    CallCleanup,
    CallCleanupSupervisor,
    TestCleanupCompletionRepository,
    TestTelephonyLeg
  }

  alias Vxpipe.Gateway.Telephony.MediaBinding

  @moduletag :integration

  for provider <- [:telnyx, :twilio], stop <- [:room, :tracker, :invalid_media, :leg_rejection] do
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

      {:ok, tracker} =
        CallCleanupSupervisor.start_new(cleanup, nil, completion_options(c.stop))

      on_exit(fn ->
        CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)

        case CallCleanupSupervisor.lookup(cleanup) do
          {:ok, owner} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, owner)
          {:error, :not_found} -> :ok
        end
      end)

      result = if c.stop == :leg_rejection, do: {:error, :media_session_not_found}, else: :ok
      leg = start_supervised!({TestTelephonyLeg, observer: self(), result: result})

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
          provider_call_leg_id: "socket-control",
          provider_call_session_id: "socket-session",
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

      code = trigger_close(c.stop, socket, room, tracker, binding)

      assert {:ok, <<0x88, length>>} = :gen_tcp.recv(socket, 2, 2_000)
      assert {:ok, <<^code::16, _reason::binary>>} = :gen_tcp.recv(socket, length, 2_000)
      :ok = :gen_tcp.send(socket, <<0x88, 0x82, 0, 0, 0, 0, code::16>>)
      assert_receive {:DOWN, ^monitor, :process, ^owner, {:shutdown, :local_closed}}, 2_000

      assert_cleanup(c.stop, room, tracker, cleanup, owner, leg)
    end
  end

  defp completion_options(stop) when stop in [:room, :tracker], do: []

  defp completion_options(_stop) do
    [
      completion: [
        calls_options: [
          call_repository: {TestCleanupCompletionRepository, self()},
          publication_enabled: false
        ],
        timeout_ms: 5_000,
        retry_ms: 1
      ]
    ]
  end

  defp trigger_close(:room, _socket, room, _tracker, _binding) do
    assert :ok = CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)
    1000
  end

  defp trigger_close(:tracker, _socket, _room, tracker, _binding) do
    assert :ok = DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
    1000
  end

  defp trigger_close(stop, socket, _room, tracker, binding) do
    # The socket cannot supply the carrier's separate termination/usage proof.
    assert :ok = CallCleanup.register(tracker, :incoming_leg, binding.leg)

    case stop do
      :invalid_media ->
        send_text(socket, "invalid JSON")
        1008

      :leg_rejection ->
        send_text(socket, JSON.encode!(start_message(binding)))
        assert_receive {:test_media_event, %{kind: :media_started}, _owner}, 2_000
        1011
    end
  end

  defp assert_cleanup(:room, _room, tracker, _cleanup, _owner, _leg) do
    assert_receive {:call_cleanup_changed, ^tracker, %{status: :complete}}, 2_000
  end

  defp assert_cleanup(:tracker, _room, _tracker, cleanup, _owner, _leg) do
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(cleanup)
  end

  defp assert_cleanup(_stop, room, tracker, cleanup, owner, leg) do
    assert :ok = CallEngine.end_call(room.tenant_id, room.room_id, room.incarnation_id)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{
                      engine_outcome: :complete,
                      status: :pending,
                      resources: %{^owner => %{root_outcome: :complete}}
                    }},
                   2_000

    refute_receive {:complete_cleanup, _, _, _}
    assert :ok = CallCleanup.acknowledge(tracker, leg, :complete)
    assert %{status: :pending} = CallCleanup.snapshot(tracker)
    monitor = Process.monitor(tracker)
    assert :ok = stop_supervised(TestTelephonyLeg)
    assert_receive {:complete_cleanup, worker, ^cleanup, %DateTime{}}, 2_000
    send(worker, :complete)
    assert_receive {:DOWN, ^monitor, :process, ^tracker, :normal}, 2_000
  end

  defp start_message(%{provider: :telnyx} = binding) do
    %{
      "event" => "start",
      "stream_id" => "socket-stream",
      "start" => %{
        "call_control_id" => binding.provider_call_control_id,
        "call_session_id" => binding.provider_call_session_id,
        "client_state" =>
          Base.encode64(JSON.encode!(%{"vxpipe_leg_id" => binding.client_state_leg_id})),
        "media_format" => %{"encoding" => "OPUS", "sample_rate" => 16_000, "channels" => 1}
      }
    }
  end

  defp start_message(%{provider: :twilio} = binding) do
    stream = "MZ" <> String.duplicate("a", 32)

    %{
      "event" => "start",
      "streamSid" => stream,
      "start" => %{
        "streamSid" => stream,
        "accountSid" => binding.provider_connection_id,
        "callSid" => binding.provider_call_control_id,
        "tracks" => ["inbound"],
        "mediaFormat" => %{"encoding" => "audio/x-mulaw", "sampleRate" => 8_000, "channels" => 1}
      }
    }
  end

  defp send_text(socket, text) do
    length = byte_size(text)
    header = if length < 126, do: <<0x81, 1::1, length::7>>, else: <<0x81, 0xFE, length::16>>
    :ok = :gen_tcp.send(socket, [header, <<0, 0, 0, 0>>, text])
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
