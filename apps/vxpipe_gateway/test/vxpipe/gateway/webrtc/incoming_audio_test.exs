defmodule Vxpipe.Gateway.WebRTC.IncomingAudioTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.IncomingAudio

  test "drops monitor audio without ending its receive-only connection" do
    attachment = %ConnectionAttachment{
      room_monitor: make_ref(),
      media_ingress: nil,
      room_audio_input_mode: :disabled,
      room_audio_output_mode: :full_mix
    }

    assert :drop =
             IncomingAudio.forward(codec(), "monitor-track", packet(),
               session: session(),
               connection_id: "conn-monitor",
               attachment: attachment,
               room_audio_ingress: nil,
               received_at: 1_000
             )
  end

  defp codec do
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  end

  defp packet do
    %Packet{
      payload_type: 111,
      sequence_number: 1,
      timestamp: 960,
      ssrc: 123,
      payload: <<1, 2, 3>>
    }
  end

  defp session do
    %Snapshot{
      session_id: "session-monitor",
      tenant_id: "tenant-demo",
      actor_id: "actor-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-monitor",
      tool_visibility: ToolVisibility.hidden(),
      expires_at: ~U[2026-09-11 07:00:00.000Z]
    }
  end
end
