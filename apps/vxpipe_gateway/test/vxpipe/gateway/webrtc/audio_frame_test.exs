defmodule Vxpipe.Gateway.WebRTC.AudioFrameTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias ExSDP.Attribute.FMTP
  alias ExWebRTC.RTPCodecParameters
  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.Media.AudioFrame, as: EngineAudioFrame
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.AudioFrame

  test "maps a negotiated Opus RTP packet into the protocol-neutral engine frame" do
    session = session_snapshot()
    payload = opus_packet(1)

    codec = %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

    packet = %Packet{
      payload_type: 111,
      sequence_number: 42,
      timestamp: 960,
      ssrc: 123,
      payload: payload
    }

    assert {:ok,
            %EngineAudioFrame{
              tenant_id: "tenant-demo",
              room_id: "room-demo",
              incarnation_id: "rinc-demo",
              participant_id: "part-human",
              connection_id: "conn-demo",
              track_id: "8472",
              codec: :opus,
              sample_rate: 48_000,
              channels: 2,
              sequence_number: 42,
              timestamp: 960,
              payload: ^payload,
              received_at: 1_000
            }} = AudioFrame.from_rtp(session, "conn-demo", 8472, codec, packet, 1_000)
  end

  test "accepts a mono Opus packet when negotiated FMTP requests stereo output" do
    payload = opus_packet(1)

    codec = %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2,
      sdp_fmtp_line: %FMTP{pt: 111, stereo: true}
    }

    packet = %Packet{
      payload_type: 111,
      sequence_number: 42,
      timestamp: 960,
      ssrc: 123,
      payload: payload
    }

    assert {:ok, %EngineAudioFrame{channels: 2, payload: ^payload}} =
             AudioFrame.from_rtp(session_snapshot(), "conn-demo", 8472, codec, packet, 1_000)
  end

  test "preserves the negotiated decode envelope for a stereo Opus packet" do
    payload = opus_packet(2)

    codec = %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

    packet = %Packet{
      payload_type: 111,
      sequence_number: 42,
      timestamp: 960,
      ssrc: 123,
      payload: payload
    }

    assert {:ok, %EngineAudioFrame{channels: 2, payload: ^payload}} =
             AudioFrame.from_rtp(session_snapshot(), "conn-demo", 8472, codec, packet, 1_000)
  end

  test "rejects an Opus RTP packet without a TOC byte" do
    codec = %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }

    packet = %Packet{
      payload_type: 111,
      sequence_number: 42,
      timestamp: 960,
      ssrc: 123,
      payload: <<>>
    }

    assert {:error, :invalid_packet} =
             AudioFrame.from_rtp(session_snapshot(), "conn-demo", 8472, codec, packet, 1_000)
  end

  test "rejects RTP whose negotiated codec is not an engine STT format" do
    codec = %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }

    packet = %Packet{
      payload_type: 96,
      sequence_number: 1,
      timestamp: 1,
      ssrc: 123,
      payload: <<1>>
    }

    assert {:error, :unsupported_codec} =
             AudioFrame.from_rtp(session_snapshot(), "conn-demo", 8472, codec, packet, 1_000)
  end

  defp session_snapshot do
    %Snapshot{
      session_id: "session-demo",
      tenant_id: "tenant-demo",
      actor_id: "actor-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      tool_visibility: Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility.hidden(),
      expires_at: ~U[2026-09-04 13:00:00.000Z]
    }
  end

  defp opus_packet(channels) when channels in [1, 2] do
    encoder = Native.create(48_000, channels, 2_048, 64_000, 3_001)

    pcm =
      for sample <- 0..959, channel <- 1..channels, into: <<>> do
        frequency = if channel == 1, do: 440, else: 660
        value = round(:math.sin(2 * :math.pi() * frequency * sample / 48_000) * 16_000)
        <<value::little-signed-16>>
      end

    assert {:ok, payload} = Native.encode_packet(encoder, pcm, 960)
    payload
  end
end
