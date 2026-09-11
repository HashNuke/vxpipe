defmodule Vxpipe.Gateway.Telephony.Telnyx.MediaDecoderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Telephony.{Adapter, Event, MediaPacket}
  alias Vxpipe.Gateway.Telephony.Telnyx.Adapter, as: TelnyxAdapter

  test "accepts an exact-leg Opus stream start" do
    message = %{
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

    assert {:ok,
            %Event{
              kind: :media_started,
              provider: :telnyx,
              provider_call_control_id: "call-control-1",
              provider_call_session_id: "call-session-1",
              stream_id: "stream-1"
            }} = decode(message)
  end

  test "decodes inbound Opus payloads using the media chunk clock" do
    message = %{
      "event" => "media",
      "sequence_number" => "9",
      "stream_id" => "stream-1",
      "media" => %{
        "track" => "inbound",
        "chunk" => "4",
        "timestamp" => "60",
        "payload" => Base.encode64(<<1, 2, 3>>)
      }
    }

    assert {:ok,
            %Event{
              kind: :media,
              provider_event_id: "stream-1:9",
              stream_id: "stream-1",
              sequence_number: 4,
              media: %MediaPacket{
                codec: :opus,
                sample_rate: 16_000,
                channels: 1,
                sequence_number: 4,
                timestamp: 60,
                payload: <<1, 2, 3>>
              }
            }} = decode(message)
  end

  test "normalizes socket DTMF with exact leg identity and occurrence time" do
    message = %{
      "event" => "dtmf",
      "sequence_number" => "10",
      "stream_id" => "stream-1",
      "occurred_at" => "2026-09-11T10:45:12.123456Z",
      "dtmf" => %{"digit" => "1"}
    }

    assert {:ok,
            %Event{
              kind: :dtmf,
              provider_event_id: "stream-1:10",
              provider_call_leg_id: "call-leg-1",
              provider_call_session_id: "call-session-1",
              digit: "1",
              occurred_at: ~U[2026-09-11 10:45:12.123456Z]
            }} = decode(message)
  end

  test "ignores connection lifecycle messages outside room control" do
    assert :ignore = decode(%{"event" => "connected", "version" => "1.0.0"})

    assert :ignore =
             decode(%{
               "event" => "stop",
               "sequence_number" => "11",
               "stream_id" => "stream-1",
               "stop" => %{"call_control_id" => "call-control-1"}
             })
  end

  test "rejects another call, stream, codec, or media direction" do
    start = %{
      "event" => "start",
      "sequence_number" => "1",
      "stream_id" => "stream-1",
      "start" => %{
        "call_control_id" => "call-control-other",
        "call_session_id" => "call-session-1",
        "client_state" => Base.encode64(JSON.encode!(%{"vxpipe_leg_id" => "leg-1"})),
        "media_format" => %{
          "encoding" => "OPUS",
          "sample_rate" => 16_000,
          "channels" => 1
        }
      }
    }

    assert {:error, :invalid_telnyx_media_message} = decode(start)

    for override <- [
          %{"stream_id" => "stream-other"},
          %{"media" => media("outbound")},
          %{"media" => Map.put(media("inbound"), "payload", "not-base64")}
        ] do
      message =
        Map.merge(
          %{
            "event" => "media",
            "sequence_number" => "9",
            "stream_id" => "stream-1",
            "media" => media("inbound")
          },
          override
        )

      assert {:error, :invalid_telnyx_media_message} = decode(message)
    end
  end

  defp decode(message) do
    Adapter.decode_media_message(TelnyxAdapter, options(), JSON.encode!(message))
  end

  defp options do
    [
      leg_id: "leg-1",
      provider_connection_id: "voice-application-1",
      provider_call_control_id: "call-control-1",
      provider_call_leg_id: "call-leg-1",
      provider_call_session_id: "call-session-1",
      stream_id: "stream-1"
    ]
  end

  defp media(track) do
    %{
      "track" => track,
      "chunk" => "4",
      "timestamp" => "60",
      "payload" => Base.encode64(<<1, 2, 3>>)
    }
  end
end
