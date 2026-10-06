defmodule Vxpipe.Providers.Twilio.MediaDecoderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, MediaPacket}
  alias Vxpipe.Providers.Twilio.Adapter, as: TwilioAdapter

  @account_sid "AC00000000000000000000000000000000"
  @call_sid "CA00000000000000000000000000000000"
  @stream_sid "MZ00000000000000000000000000000000"
  @received_at DateTime.to_unix(~U[2026-09-11 18:00:00Z])

  test "normalizes the exact start identity and media format" do
    assert {:ok,
            %Event{
              kind: :media_started,
              provider: :twilio,
              provider_connection_id: @account_sid,
              provider_call_control_id: @call_sid,
              provider_call_leg_id: @call_sid,
              provider_call_session_id: nil,
              stream_id: @stream_sid
            }} = decode(start_message())
  end

  test "normalizes bounded inbound PCMU media with provider timing" do
    assert {:ok,
            %Event{
              kind: :media,
              provider_event_id: "#{@stream_sid}:2",
              stream_id: @stream_sid,
              sequence_number: 1,
              media: %MediaPacket{
                codec: :pcmu,
                sample_rate: 8_000,
                channels: 1,
                sequence_number: 1,
                timestamp: 20,
                payload: <<255, 127, 0>>
              }
            }} = decode(media_message())
  end

  test "normalizes inbound DTMF using gateway observation time" do
    message = %{
      "event" => "dtmf",
      "sequenceNumber" => "3",
      "streamSid" => @stream_sid,
      "dtmf" => %{"track" => "inbound_track", "digit" => "1"}
    }

    assert {:ok,
            %Event{
              kind: :dtmf,
              provider_event_id: "#{@stream_sid}:3",
              occurred_at: ~U[2026-09-11 18:00:00Z],
              stream_id: @stream_sid,
              digit: "1"
            }} = decode(message)
  end

  test "accepts both inbound DTMF track labels without accepting an outbound track" do
    message = %{
      "event" => "dtmf",
      "sequenceNumber" => "3",
      "streamSid" => @stream_sid,
      "dtmf" => %{"track" => "inbound", "digit" => "1"}
    }

    assert {:ok, %Event{kind: :dtmf, digit: "1"}} = decode(message)

    for track <- ["outbound", "outbound_track", nil, "unexpected"] do
      assert {:error, :invalid_twilio_media_message} =
               decode(put_in(message, ["dtmf", "track"], track))
    end

    assert {:error, :invalid_twilio_media_message} =
             decode(Map.put(message, "streamSid", "MZffffffffffffffffffffffffffffffff"))
  end

  test "rejects a start frame for another call before media attachment" do
    message = put_in(start_message(), ["start", "callSid"], "CAffffffffffffffffffffffffffffffff")

    assert {:error, :invalid_twilio_media_message} = decode(message)
  end

  test "a matching bidirectional stop is a terminal call event" do
    message = %{
      "event" => "stop",
      "sequenceNumber" => "5",
      "streamSid" => @stream_sid,
      "stop" => %{"accountSid" => @account_sid, "callSid" => @call_sid}
    }

    assert {:ok,
            %Event{
              kind: :ended,
              provider_event_id: "#{@stream_sid}:5",
              occurred_at: ~U[2026-09-11 18:00:00Z],
              stream_id: @stream_sid,
              end_reason: :hangup
            }} = decode(message)

    for {path, other} <- [
          {["streamSid"], "MZffffffffffffffffffffffffffffffff"},
          {["stop", "accountSid"], "ACffffffffffffffffffffffffffffffff"},
          {["stop", "callSid"], "CAffffffffffffffffffffffffffffffff"}
        ] do
      assert {:error, :invalid_twilio_media_message} = decode(put_in(message, path, other))
    end
  end

  test "ignores authenticated protocol and playback acknowledgement frames" do
    assert :ignore = decode(%{"event" => "connected", "protocol" => "Call", "version" => "1.0.0"})

    assert :ignore =
             decode(%{
               "event" => "mark",
               "sequenceNumber" => "4",
               "streamSid" => @stream_sid,
               "mark" => %{"name" => "vxp-1"}
             })
  end

  defp decode(message) do
    Adapter.decode_media_message(TwilioAdapter, decoder_options(), JSON.encode!(message))
  end

  defp decoder_options do
    [
      provider_connection_id: @account_sid,
      provider_call_control_id: @call_sid,
      provider_call_leg_id: @call_sid,
      provider_call_session_id: nil,
      stream_id: @stream_sid,
      received_at: @received_at
    ]
  end

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
        "timestamp" => "20",
        "payload" => Base.encode64(<<255, 127, 0>>)
      }
    }
  end
end
