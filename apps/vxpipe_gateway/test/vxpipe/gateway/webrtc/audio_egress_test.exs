defmodule Vxpipe.Gateway.WebRTC.AudioEgressTest do
  use ExUnit.Case, async: true

  alias ExRTP.Packet
  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, NormalizedFrame, OutputSink}
  alias Vxpipe.CallEngine.Recording.EgressHandoff
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 4,
         progress_interval_packets: 1,
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
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:progress, 20, 40}}
    assert_receive {:test_pcm_encoded, final_pcm}
    assert byte_size(final_pcm) == 1_920
    assert binary_part(final_pcm, 0, 4) == <<1, 0, 2, 0>>

    assert_receive {:test_rtp, %Packet{sequence_number: 1, timestamp: 960}}
    assert_receive {:test_scheduled, ^egress, completion_message, 20}

    send(egress, completion_message)
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:completed, 40}}
  end

  test "backpressures a provider burst while the bounded packet queue drains" do
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 1,
         send_rtp: sender,
         schedule: schedule}
      )

    burst = :binary.copy(<<0>>, 3 * 1_920)
    burst_frame = frame(burst)
    task_supervisor = start_supervised!(Task.Supervisor)

    push =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        GenServer.call(egress, {:vxpipe_audio_output, burst_frame})
      end)

    assert_receive {:test_rtp, %Packet{sequence_number: 0}}
    assert_receive {:test_scheduled, ^egress, first_pace, 20}
    assert Task.yield(push, 0) == nil

    send(egress, first_pace)
    assert_receive {:test_rtp, %Packet{sequence_number: 1}}
    assert_receive {:test_scheduled, ^egress, second_pace, 20}
    assert Task.yield(push, 0) == nil

    send(egress, second_pace)
    assert_receive {:test_rtp, %Packet{sequence_number: 2}}
    assert_receive {:test_scheduled, ^egress, final_pace, 20}
    assert Task.await(push) == :ok

    assert :ok =
             GenServer.call(egress, {:vxpipe_audio_output_finish, "turn-test", self()})

    send(egress, final_pace)
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:completed, 60}}
  end

  test "backpressures final PCM padding until the packet queue has room" do
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 1,
         send_rtp: sender,
         schedule: schedule}
      )

    assert :ok =
             GenServer.call(egress, {
               :vxpipe_audio_output,
               frame(:binary.copy(<<0>>, 1_920))
             })

    assert_receive {:test_rtp, %Packet{sequence_number: 0}}
    assert_receive {:test_scheduled, ^egress, first_pace, 20}

    assert :ok =
             GenServer.call(egress, {
               :vxpipe_audio_output,
               frame(:binary.copy(<<0>>, 1_924))
             })

    task_supervisor = start_supervised!(Task.Supervisor)

    finish =
      Task.Supervisor.async_nolink(task_supervisor, fn ->
        GenServer.call(egress, {:vxpipe_audio_output_finish, "turn-test", test_process})
      end)

    assert Task.yield(finish, 100) == nil

    send(egress, first_pace)
    assert_receive {:test_rtp, %Packet{sequence_number: 1}}
    assert_receive {:test_scheduled, ^egress, second_pace, 20}
    assert Task.yield(finish, 0) == nil

    send(egress, second_pace)
    assert_receive {:test_rtp, %Packet{sequence_number: 2}}
    assert_receive {:test_scheduled, ^egress, final_pace, 20}
    assert Task.await(finish) == :ok

    send(egress, final_pace)
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:completed, 60}}
  end

  test "rejects audio for the wrong connection" do
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
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
  end

  test "interrupts a turn after confirmed playout and drops its queued packets" do
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 4,
         send_rtp: sender,
         schedule: schedule}
      )

    assert :ok =
             GenServer.call(egress, {
               :vxpipe_audio_output,
               frame(:binary.copy(<<0>>, 3 * 1_920))
             })

    assert_receive {:test_rtp, %Packet{sequence_number: 0}}
    assert_receive {:test_scheduled, ^egress, first_pace, 20}

    send(egress, first_pace)
    assert_receive {:test_rtp, %Packet{sequence_number: 1}}
    assert_receive {:test_scheduled, ^egress, stale_pace, 20}

    assert {:ok, 20} =
             GenServer.call(
               egress,
               {:vxpipe_audio_output_interrupt, "turn-test", self()}
             )

    send(egress, stale_pace)
    refute_receive {:test_rtp, %Packet{sequence_number: 2}}
    refute_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:completed, _played_ms}}

    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(<<0::size(15_360)>>)})
    assert_receive {:test_rtp, %Packet{sequence_number: 2, marker: true}}
  end

  test "records only PCM whose RTP packet was accepted before interruption" do
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
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         maximum_packets: 4,
         send_rtp: sender,
         schedule: schedule}
      )

    handoff = recording_handoff("connection-test")
    assert {:error, :recording_not_bound} = AudioEgress.recording_binding(egress)
    assert :ok = OutputSink.bind_recording(egress, handoff)

    assert {:ok, resource, ^handoff, %{sample_rate: 48_000, channels: 1}} =
             AudioEgress.recording_binding(egress)

    assert {:ok, ^resource, :ready} = AudioEgress.readiness(egress)

    first = :binary.copy(<<1, 0>>, 960)
    queued = :binary.copy(<<2, 0>>, 2 * 960)
    assert :ok = GenServer.call(egress, {:vxpipe_audio_output, frame(first <> queued)})

    assert_receive {:test_rtp, %Packet{sequence_number: 0}}

    assert_receive {:vxpipe_recording_egress, ^handoff,
                    %NormalizedFrame{
                      source_participant_id: "agent-test",
                      connection_id: "connection-test",
                      track_id: "agent-egress",
                      payload: ^first
                    }}

    :ok = EgressHandoff.release(handoff)
    assert_receive {:test_scheduled, ^egress, stale_pace, 20}

    assert {:ok, 0} =
             GenServer.call(
               egress,
               {:vxpipe_audio_output_interrupt, "turn-test", self()}
             )

    send(egress, stale_pace)
    refute_receive {:vxpipe_recording_egress, ^handoff, %NormalizedFrame{}}
  end

  test "private wait audio plays without entering the WebRTC recording handoff" do
    observer = self()

    egress =
      start_supervised!(
        {AudioEgress,
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         send_rtp: fn _, _, packet ->
           send(observer, {:test_rtp, packet})
           :ok
         end,
         schedule: fn target, message, _ ->
           send(observer, {:pace, target, message})
           make_ref()
         end}
      )

    handoff = recording_handoff("connection-test")
    assert :ok = OutputSink.bind_recording(egress, handoff)
    private = frame(:binary.copy(<<1, 0>>, 960)) |> Map.put(:audio_scope, :private)
    assert :ok = OutputSink.push(egress, private)
    assert :ok = OutputSink.finish(egress, "turn-test", self())
    assert_receive {:test_rtp, %Packet{sequence_number: 0}}
    assert_receive {:pace, ^egress, message}
    send(egress, message)
    assert_receive {:vxpipe_audio_playback, ^egress, "turn-test", {:completed, 20}}
    refute_receive {:vxpipe_recording_egress, ^handoff, _}
  end

  test "phase clearing drains the sent packet and retains the encoder and RTP timeline" do
    observer = self()

    egress =
      start_supervised!(
        {AudioEgress,
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: "connection-test",
         peer_connection: self(),
         track_id: "track-output",
         encoder: {TestOpusEncoder, [observer: self()]},
         send_rtp: fn _, _, packet ->
           send(observer, {:test_rtp, packet})
           :ok
         end,
         schedule: fn target, message, _ ->
           send(observer, {:pace, target, message})
           make_ref()
         end}
      )

    assert {:ok, resource, :ready} = AudioEgress.readiness(egress)
    assert resource.instance == egress
    assert resource.scope == {:participant, "caller-test"}
    assert resource.binding == "connection-test"
    assert :ok = OutputSink.push(egress, frame(:binary.copy(<<1, 0>>, 3 * 960)))
    assert_receive {:test_rtp, %Packet{sequence_number: 0, timestamp: 0, ssrc: ssrc}}
    assert_receive {:pace, ^egress, message}
    encoder = :sys.get_state(egress).encoder
    request = :gen_server.send_request(egress, :vxpipe_audio_output_clear)
    _ = :sys.get_state(egress)
    assert :timeout = :gen_server.wait_response(request, 0)
    send(egress, message)
    assert {:reply, {:ok, 20}} = :gen_server.wait_response(request, 1_000)
    assert :sys.get_state(egress).encoder == encoder
    assert {:ok, ^resource, :ready} = AudioEgress.readiness(egress)
    assert :ok = OutputSink.push(egress, frame(:binary.copy(<<2, 0>>, 960)))
    assert_receive {:test_rtp, %Packet{sequence_number: 1, timestamp: 960, ssrc: ^ssrc}}
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

  defp recording_handoff(connection_id) do
    counters = EgressHandoff.new_counters()
    :ok = EgressHandoff.install_policy(counters, 0, true)

    EgressHandoff.new(
      self(),
      make_ref(),
      %{
        tenant_id: "tenant-test",
        room_id: "room-test",
        incarnation_id: "incarnation-test"
      },
      %{
        channels: 1,
        clock: fn -> 0 end,
        clock_origin_ms: 0,
        frame_samples: 960,
        gate: counters,
        sample_rate: 48_000
      },
      connection_id,
      4,
      counters
    )
  end
end
