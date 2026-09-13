defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaSocketTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.{IngressIdentity, LegSupervisor, MediaBinding}
  alias Vxpipe.Gateway.Telephony.Telnyx.MediaSocket
  alias Vxpipe.Gateway.TestTelephonyCallBackend

  setup do
    backend = start_supervised!({TestTelephonyCallBackend, observer: self()})
    identity = identity()
    event = incoming_event()

    assert {:ok, leg} =
             LegSupervisor.start(
               LegSupervisor,
               identity,
               event,
               TestTelephonyCallBackend.backend(backend),
               fn -> ~U[2026-09-11 10:40:01.000000Z] end
             )

    assert :ok = Vxpipe.Gateway.Telephony.Leg.await(leg, 1_000)
    on_exit(fn -> LegSupervisor.stop(:telnyx, "primary-phone", "call-leg-1") end)

    binding = media_binding(leg)
    assert {:ok, socket} = MediaSocket.init(%{binding: binding})

    %{binding: binding, socket: socket}
  end

  test "pins the start frame and dispatches only that stream to the exact leg", context do
    assert {:ok, socket} =
             MediaSocket.handle_in({JSON.encode!(start_message()), opcode: :text}, context.socket)

    assert_receive {:test_live_telephony_event,
                    %Event{kind: :media_started, stream_id: "stream-1"}, source}

    assert source == self()

    assert {:ok, _socket} =
             MediaSocket.handle_in({JSON.encode!(media_message()), opcode: :text}, socket)

    assert_receive {:test_live_telephony_event,
                    %Event{
                      kind: :media,
                      stream_id: "stream-1",
                      provider_call_leg_id: "call-leg-1"
                    }, ^source}
  end

  test "closes on a frame that does not belong to the pinned call", context do
    invalid = put_in(start_message(), ["start", "call_control_id"], "call-control-other")

    assert {:stop, :invalid_media_message, {1008, "invalid media message"}, _socket} =
             MediaSocket.handle_in({JSON.encode!(invalid), opcode: :text}, context.socket)

    refute_receive {:test_live_telephony_event, _event}
  end

  test "pushes an encoded egress envelope back over the same socket", context do
    message = JSON.encode!(%{"event" => "media", "media" => %{"payload" => "AQI="}})

    assert {:push, {:text, ^message}, _socket} =
             MediaSocket.handle_info({:vxpipe_telnyx_socket_send, message}, context.socket)
  end

  test "drain waits for its exact mark and clear cancels older marks", context do
    assert {:ok, socket} =
             MediaSocket.handle_in({JSON.encode!(start_message()), opcode: :text}, context.socket)

    first = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, "stream-1", :drain, self(), first},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]
    refute_receive {:vxpipe_playback_ack, ^first, _}
    clear = make_ref()

    assert {:push, [{:text, clear_json}, {:text, after_clear}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, "stream-1", :clear, self(), clear},
               socket
             )

    assert JSON.decode!(clear_json) == %{"event" => "clear"}
    assert_receive {:vxpipe_playback_ack, ^first, {:error, :cleared}}
    assert {:ok, socket} = MediaSocket.handle_in(mark_message(name), socket)
    refute_receive {:vxpipe_playback_ack, ^clear, _}
    name = JSON.decode!(after_clear)["mark"]["name"]
    assert {:ok, socket} = MediaSocket.handle_in(mark_message(name), socket)
    assert_receive {:vxpipe_playback_ack, ^clear, :ok}
    assert {:ok, _socket} = MediaSocket.handle_in(mark_message(name), socket)
    refute_receive {:vxpipe_playback_ack, _, _}
  end

  test "a foreign stream cannot acknowledge an outstanding drain", context do
    assert {:ok, socket} =
             MediaSocket.handle_in({JSON.encode!(start_message()), opcode: :text}, context.socket)

    request = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, "stream-1", :drain, self(), request},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]

    assert {:stop, :invalid_media_message, _, _} =
             MediaSocket.handle_in(mark_message(name, "other"), socket)

    refute_receive {:vxpipe_playback_ack, ^request, _}
  end

  test "processes playback marks while the call event dispatcher is busy", context do
    leg = context.binding.leg
    :ok = :sys.suspend(leg)

    on_exit(fn ->
      try do
        :sys.resume(leg)
      catch
        :exit, _ -> :ok
      end
    end)

    assert {:ok, socket} =
             MediaSocket.handle_in({JSON.encode!(start_message()), opcode: :text}, context.socket)

    request = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, "stream-1", :drain, self(), request},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]
    assert {:ok, _socket} = MediaSocket.handle_in(mark_message(name), socket)
    assert_receive {:vxpipe_playback_ack, ^request, :ok}
    :ok = :sys.resume(leg)
  end

  defp mark_message(name, stream \\ "stream-1") do
    {JSON.encode!(%{
       "event" => "mark",
       "stream_id" => stream,
       "sequence_number" => "4",
       "mark" => %{"name" => name}
     }), opcode: :text}
  end

  defp start_message do
    %{
      "event" => "start",
      "sequence_number" => "1",
      "stream_id" => "stream-1",
      "start" => %{
        "call_control_id" => "call-control-1",
        "call_session_id" => "call-session-1",
        "client_state" => Base.encode64(JSON.encode!(%{"vxpipe_leg_id" => "leg-1"})),
        "media_format" => %{
          "encoding" => "OPUS",
          "sample_rate" => 16_000,
          "channels" => 1
        }
      }
    }
  end

  defp media_message do
    %{
      "event" => "media",
      "sequence_number" => "2",
      "stream_id" => "stream-1",
      "media" => %{
        "track" => "inbound",
        "chunk" => "1",
        "timestamp" => "0",
        "payload" => Base.encode64(<<1, 2, 3>>)
      }
    }
  end

  defp media_binding(leg) do
    %MediaBinding{
      provider: :telnyx,
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      tenant_id: "tenant-demo",
      call_id: "call-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-caller",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      client_state_leg_id: "leg-1",
      leg: leg
    }
  end

  defp identity do
    %IngressIdentity{
      service_id: "primary-phone",
      ingress_key: "ingress-primary",
      scope: {:tenant, "AAAAAAAAAAAAAAAA"},
      provider: :telnyx,
      provider_connection_id: "voice-application-1"
    }
  end

  defp incoming_event do
    %Event{
      kind: :incoming,
      provider: :telnyx,
      provider_event_id: "event-incoming-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      occurred_at: ~U[2026-09-11 10:39:59.000000Z],
      from: "+15550001001",
      to: "+15550001000"
    }
  end
end
