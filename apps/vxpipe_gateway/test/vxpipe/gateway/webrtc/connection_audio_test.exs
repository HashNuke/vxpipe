defmodule Vxpipe.Gateway.WebRTC.ConnectionAudioTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias ExWebRTC.RTPCodecParameters
  alias Membrane.Opus.Encoder.Native
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolVisibility
  alias Vxpipe.Gateway.Session.Snapshot
  alias Vxpipe.Gateway.WebRTC.{Connection, SpeechInput}

  test "an empty Opus packet does not terminate an admitted connection" do
    state = connection_state(attachment(:enabled))

    assert {:noreply, ^state} =
             Connection.handle_info(rtp_message(packet(<<>>)), state)
  end

  test "stereo input is ignored before inspection on a receive-only connection" do
    state = connection_state(attachment(:disabled))

    assert {:noreply, ^state} =
             Connection.handle_info(rtp_message(packet(stereo_opus_packet())), state)
  end

  test "a malformed nonempty Opus packet is dropped after speech validation" do
    track = %{track_id: "track-input", codec: :opus, sample_rate: 48_000, channels: 2}
    assert {:ok, _output, input} = SpeechInput.configure(track, target(:linear16))
    input = Map.put(input, :ingress, self())

    state =
      :enabled
      |> attachment(self())
      |> connection_state()
      |> Map.put(:speech_input, input)

    assert {:noreply, ^state} =
             Connection.handle_info(rtp_message(packet(<<255>>)), state)
  end

  defp connection_state(attachment) do
    %{
      peer_connection: self(),
      audio_tracks: %{"track-input" => %{111 => codec()}},
      attachment: attachment,
      speech_input: nil,
      room_audio_ingress: nil,
      session: session(),
      connection_id: "conn-demo"
    }
  end

  defp rtp_message(packet) do
    {:ex_webrtc, self(), {:rtp, "track-input", nil, packet}}
  end

  defp attachment(input_mode, media_ingress \\ nil) do
    %ConnectionAttachment{
      room_monitor: make_ref(),
      media_ingress: media_ingress,
      room_audio_input_mode: input_mode,
      room_audio_output_mode: :full_mix
    }
  end

  defp target(codec), do: %{codec: codec, sample_rate: 48_000, channels: 1}

  defp codec do
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  end

  defp packet(payload) do
    %Packet{
      payload_type: 111,
      sequence_number: 1,
      timestamp: 960,
      ssrc: 123,
      payload: payload
    }
  end

  defp stereo_opus_packet do
    encoder = Native.create(48_000, 2, 2_048, 64_000, 3_001)

    pcm =
      for _sample <- 0..959, into: <<>> do
        <<1_000::little-signed-16, -500::little-signed-16>>
      end

    assert {:ok, payload} = Native.encode_packet(encoder, pcm, 960)
    payload
  end

  defp session do
    %Snapshot{
      session_id: "session-demo",
      tenant_id: "tenant-demo",
      actor_id: "actor-demo",
      room_id: "room-demo",
      incarnation_id: "rinc-demo",
      participant_id: "part-human",
      tool_visibility: ToolVisibility.hidden(),
      expires_at: ~U[2026-09-20 13:00:00.000Z]
    }
  end
end
