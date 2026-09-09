defmodule Vxpipe.Gateway.WebRTC.AudioFrameTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Vxpipe.CallEngine.Media.AudioFrame, as: EngineAudioFrame
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.AudioFrame

  test "maps a negotiated Opus RTP packet into the protocol-neutral engine frame" do
    session = session_snapshot()

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
      payload: <<1, 2, 3>>
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
              payload: <<1, 2, 3>>,
              received_at: 1_000
            }} = AudioFrame.from_rtp(session, "conn-demo", 8472, codec, packet, 1_000)
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
end
