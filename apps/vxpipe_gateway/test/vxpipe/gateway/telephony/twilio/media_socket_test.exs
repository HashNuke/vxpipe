defmodule Vxpipe.Gateway.Telephony.Twilio.MediaSocketTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.Event
  alias Vxpipe.Gateway.Telephony.MediaBinding
  alias Vxpipe.Gateway.Telephony.Twilio.MediaSocket
  alias Vxpipe.Gateway.TestTelephonyLeg

  @account_sid "AC00000000000000000000000000000000"
  @call_sid "CA00000000000000000000000000000000"
  @stream_sid "MZ00000000000000000000000000000000"

  setup do
    leg = start_supervised!({TestTelephonyLeg, observer: self()})
    clock = fn -> DateTime.to_unix(~U[2026-09-11 18:00:00Z]) end
    binding = media_binding(leg)
    assert {:ok, socket} = MediaSocket.init(%{binding: binding, clock: clock})
    %{binding: binding, leg: leg, socket: socket}
  end

  test "pins one start stream and dispatches its media and DTMF", context do
    assert {:ok, socket} = MediaSocket.handle_in(text(start_message()), context.socket)

    assert_receive {:test_media_event, %Event{kind: :media_started, stream_id: @stream_sid},
                    source}

    assert source == self()

    assert {:ok, socket} = MediaSocket.handle_in(text(media_message()), socket)

    assert_receive {:test_media_event,
                    %Event{
                      kind: :media,
                      stream_id: @stream_sid,
                      provider_call_leg_id: @call_sid
                    }, ^source}

    assert {:ok, _socket} = MediaSocket.handle_in(text(dtmf_message()), socket)
    assert_receive {:test_media_event, %Event{kind: :dtmf, digit: "1"}, ^source}
  end

  test "closes on a start frame for another bound call", context do
    invalid = put_in(start_message(), ["start", "callSid"], "CAffffffffffffffffffffffffffffffff")

    assert {:stop, :invalid_media_message, {1008, "invalid media message"}, _socket} =
             MediaSocket.handle_in(text(invalid), context.socket)

    refute_receive {:test_media_event, _event, _source}
  end

  test "closes normally when the exact leg owner ends", context do
    monitor = Process.monitor(context.leg)
    GenServer.stop(context.leg)
    assert_receive {:DOWN, ^monitor, :process, _leg, :normal}
    assert_receive down

    assert {:stop, :normal, {1000, "leg ended"}, _socket} =
             MediaSocket.handle_info(down, context.socket)
  end

  test "pushes internally encoded media envelopes to the provider", context do
    assert {:ok, socket} = MediaSocket.handle_in(text(start_message()), context.socket)

    message =
      JSON.encode!(%{
        "event" => "media",
        "streamSid" => @stream_sid,
        "media" => %{"payload" => Base.encode64(<<0xFF>>)}
      })

    assert {:push, {:text, ^message}, socket} =
             MediaSocket.handle_info({:vxpipe_twilio_socket_send, message}, socket)

    assert socket.stream_id == @stream_sid
  end

  test "drain waits for its exact mark and clear cancels older marks", context do
    assert {:ok, socket} = MediaSocket.handle_in(text(start_message()), context.socket)
    first = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, @stream_sid, :drain, self(), first},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]
    refute_receive {:vxpipe_playback_ack, ^first, _}

    clear = make_ref()

    assert {:push, [{:text, clear_json}, {:text, after_clear}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, @stream_sid, :clear, self(), clear},
               socket
             )

    assert JSON.decode!(clear_json) == %{"event" => "clear", "streamSid" => @stream_sid}
    assert_receive {:vxpipe_playback_ack, ^first, {:error, :cleared}}
    assert {:ok, socket} = MediaSocket.handle_in(text(mark_message(name)), socket)
    refute_receive {:vxpipe_playback_ack, ^clear, _}
    name = JSON.decode!(after_clear)["mark"]["name"]
    assert {:ok, socket} = MediaSocket.handle_in(text(mark_message(name)), socket)
    assert_receive {:vxpipe_playback_ack, ^clear, :ok}
    assert {:ok, _socket} = MediaSocket.handle_in(text(mark_message(name)), socket)
    refute_receive {:vxpipe_playback_ack, _, _}
  end

  test "a foreign stream cannot acknowledge an outstanding drain", context do
    assert {:ok, socket} = MediaSocket.handle_in(text(start_message()), context.socket)
    request = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, @stream_sid, :drain, self(), request},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]
    message = Map.put(mark_message(name), "streamSid", "MZffffffffffffffffffffffffffffffff")
    assert {:stop, :invalid_media_message, _, _} = MediaSocket.handle_in(text(message), socket)
    refute_receive {:vxpipe_playback_ack, ^request, _}
  end

  test "processes playback marks while the call event dispatcher is busy", context do
    :ok = :sys.suspend(context.leg)

    on_exit(fn ->
      try do
        :sys.resume(context.leg)
      catch
        :exit, _ -> :ok
      end
    end)

    assert {:ok, socket} = MediaSocket.handle_in(text(start_message()), context.socket)
    request = make_ref()

    assert {:push, [{:text, mark}], socket} =
             MediaSocket.handle_info(
               {:vxpipe_playback_command, @stream_sid, :drain, self(), request},
               socket
             )

    name = JSON.decode!(mark)["mark"]["name"]
    assert {:ok, _socket} = MediaSocket.handle_in(text(mark_message(name)), socket)
    assert_receive {:vxpipe_playback_ack, ^request, :ok}
    :ok = :sys.resume(context.leg)
  end

  defp mark_message(name),
    do: %{
      "event" => "mark",
      "streamSid" => @stream_sid,
      "sequenceNumber" => "4",
      "mark" => %{"name" => name}
    }

  defp text(message), do: {JSON.encode!(message), opcode: :text}

  defp start_message do
    %{
      "event" => "start",
      "sequenceNumber" => "1",
      "streamSid" => @stream_sid,
      "start" => %{
        "accountSid" => @account_sid,
        "callSid" => @call_sid,
        "streamSid" => @stream_sid,
        "tracks" => ["inbound"],
        "mediaFormat" => %{
          "encoding" => "audio/x-mulaw",
          "sampleRate" => 8_000,
          "channels" => 1
        },
        "customParameters" => %{}
      }
    }
  end

  defp media_message do
    %{
      "event" => "media",
      "sequenceNumber" => "2",
      "streamSid" => @stream_sid,
      "media" => %{
        "track" => "inbound",
        "chunk" => "1",
        "timestamp" => "0",
        "payload" => Base.encode64(:binary.copy(<<255>>, 160))
      }
    }
  end

  defp dtmf_message do
    %{
      "event" => "dtmf",
      "sequenceNumber" => "3",
      "streamSid" => @stream_sid,
      "dtmf" => %{"track" => "inbound_track", "digit" => "1"}
    }
  end

  defp media_binding(leg) do
    %MediaBinding{
      provider: :twilio,
      service_id: "twilio-primary",
      ingress_key: "ingress_twilio_primary",
      tenant_id: "tenantkey1234567",
      call_id: "call-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-caller",
      provider_connection_id: @account_sid,
      provider_call_control_id: @call_sid,
      provider_call_leg_id: @call_sid,
      provider_call_session_id: nil,
      client_state_leg_id: "leg-1",
      leg: leg
    }
  end
end
