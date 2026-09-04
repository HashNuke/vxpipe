defmodule Vxpipe.Gateway.WebRTC.AudioEgressTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.Gateway.TestOpusEncoder
  alias Vxpipe.Gateway.WebRTC.AudioEgress

  test "reframes split PCM, paces RTP, pads the tail, and acknowledges playout" do
    test_process = self()

    sender = fn _peer, "track-output", %Packet{} = packet ->
      send(test_process, {:test_rtp, packet})
      :ok
    end

    schedule = fn target, message, milliseconds ->
      send(test_process, {:test_scheduled, target, message, milliseconds})
      make_ref()
    end

    egress =
      start_supervised!(
        {AudioEgress,
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 4,
         send_rtp: sender,
         schedule: schedule}
      )

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(<<0::size(8_000)>>)})
    refute_receive {:test_rtp, _packet}

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(<<0::size(7_360)>>)})
    assert_receive {:test_pcm_encoded, pcm}
    assert byte_size(pcm) == 1_920

    assert_receive {:test_rtp,
                    %Packet{sequence_number: 0, timestamp: 0, payload: <<0xF8, 0xFF, 0xFE>>}}

    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", :started}
    assert_receive {:test_scheduled, ^egress, pace_message, 20}

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(<<1, 0, 2, 0>>)})

    assert :ok =
             GenServer.call(
               egress,
               {:vxpipe_audio_output_finish, "turn-test", self()}
             )

    send(egress, pace_message)
    assert_receive {:test_pcm_encoded, final_pcm}
    assert byte_size(final_pcm) == 1_920
    assert binary_part(final_pcm, 0, 4) == <<1, 0, 2, 0>>

    assert_receive {:test_rtp, %Packet{sequence_number: 1, timestamp: 960}}
    assert_receive {:test_scheduled, ^egress, completion_message, 20}

    send(egress, completion_message)
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", :completed}
  end

  test "rejects the wrong connection and an overflowing packet queue" do
    test_process = self()

    sender = fn _peer, _track, packet ->
      send(test_process, {:test_rtp, packet})
      :ok
    end

    schedule = fn target, message, milliseconds ->
      send(test_process, {:test_scheduled, target, message, milliseconds})
      make_ref()
    end

    egress =
      start_supervised!(
        {AudioEgress,
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 1,
         send_rtp: sender,
         schedule: schedule}
      )

    wrong = %{frame(<<0, 0>>) | connection_id: "other"}
    assert {:error, :wrong_connection} = GenServer.call(egress, {:vxpipe_audio_output, wrong})

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(:binary.copy(<<0>>, 1_920))})
    assert_receive {:test_rtp, _packet}

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(:binary.copy(<<0>>, 1_920))})

    assert {:error, :queue_full} =
             GenServer.call(egress, {:vxpipe_audio_output, frame(:binary.copy(<<0>>, 1_920))})
  end

  defp frame(payload) do
    %AudioOutputFrame{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "turn-test",
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: payload,
      reply_to: self()
    }
  end
end
