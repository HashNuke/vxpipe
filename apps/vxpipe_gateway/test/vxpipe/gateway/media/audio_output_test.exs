defmodule Vxpipe.Gateway.Media.AudioOutputTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, NormalizedFrame, OutputSink}
  alias Vxpipe.CallEngine.MediaPolicy.{Effective, Enforcer, Snapshot}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.CallEngine.Recording.EgressReadiness
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.{RoomMixer, RoomRecording, TestRecordingWriter}
  alias Vxpipe.Gateway.Media.{AudioOutput, PlaybackFrame}

  test "prepares the phone output recording writer before speech and waits for its codec" do
    {output, connection_id} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _pipeline, ^output}

    identity = %{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test"
    }

    token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             recording_token: token,
             register: false,
             sample_rate: 48_000,
             channels: 1,
             frame_samples: 960,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 20
           ]}
      )

    policy = %Snapshot{
      revision: 0,
      present_participant_ids: MapSet.new(["caller-test", "agent-test"]),
      effective: %Effective{
        audio_routes: :unrestricted,
        transcript_routes: :unrestricted,
        record_audio: true,
        save_transcripts: true
      }
    }

    :ok = Enforcer.apply(mixer, policy, 1_000)
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, connection_id)
    :ok = OutputSink.bind_recording(output, handoff)
    assert {:ok, native, :preparing} = AudioOutput.readiness(output)

    connection =
      Map.merge(identity, %{participant_id: "caller-test", connection_id: connection_id})

    assert {:ok, binding} = EgressReadiness.prepare(native, connection, mixer, policy)
    assert binding.status == :preparing

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(identity) ++
           [
             call_id: "call-test",
             mixer: mixer,
             recording_token: token,
             targets: [{:individual_tracks, ["agent-test"]}],
             writer: {TestRecordingWriter, observer: self()},
             maximum_pull_frames: 20
           ]}
      )

    mode = {:individual_track, "agent-test", connection_id, binding.track_id}
    :ok = RoomRecording.prepare_tracks(recording, [mode], 0)
    assert_receive {:test_recording_writer_opened, _worker, ^recording, %{mode: ^mode}}
    assert {:ok, writers} = RoomRecording.readiness_resources(recording)

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: identity.incarnation_id,
         attempt_id: "phone-recording",
         resources: [binding.resource | writers],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :preparing, blockers: [%{kind: :recording_output}]}},
                   1_000

    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    :ok = Collector.refresh(collector)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, current, :ready} = EgressReadiness.readiness_binding(binding.resource)
    assert current == binding.resource
    assert {:ok, 0} = OutputSink.clear(output)
    assert {:ok, ^native, :ready} = AudioOutput.readiness(output)
    refute_receive {:test_recording_chunk, _id, _chunk}
  end

  test "readiness waits for the actual codec generation and preserves it through clear" do
    {output, connection_id} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, first_id, _pipeline, ^output}
    assert {:ok, pending, :preparing} = AudioOutput.readiness(output)
    assert pending.scope == {:participant, "caller-test"}
    assert pending.binding == connection_id
    send(output, {:vxpipe_audio_output_pipeline_ready, first_id})
    assert {:ok, resource, :ready} = AudioOutput.readiness(output)
    assert {:ok, 0} = OutputSink.clear(output)
    assert {:ok, ^resource, :ready} = AudioOutput.readiness(output)
    refute_receive {:test_audio_output_pipeline_stopped, _id, _pipeline}

    assert :ok = push(output, connection_id, :binary.copy(<<0>>, 1_920))
    assert_receive {:test_audio_output_pipeline_push, ^first_id, _frame}
    assert {:ok, 0} = interrupt(output)
    assert_receive {:test_audio_output_pipeline_started, next_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, first_id})
    assert {:ok, replacement, :preparing} = AudioOutput.readiness(output)
    refute replacement.generation == resource.generation
    assert replacement.configuration == resource.configuration
    send(output, {:vxpipe_audio_output_pipeline_ready, next_id})
    assert {:ok, ^replacement, :ready} = AudioOutput.readiness(output)
  end

  test "frames streamed PCM and reports only transport-acknowledged playout" do
    {output, connection_id} = start_output(maximum_frames: 4, progress_interval_frames: 1)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    assert :ok = AudioOutput.await_ready(output)

    assert :ok = push(output, connection_id, <<0::size(8_000)>>)
    refute_receive {:test_audio_output_pipeline_push, ^pipeline_id, _frame}

    assert :ok = push(output, connection_id, <<0::size(7_360)>>)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{sequence_number: 0, timestamp: 0, payload: pcm}}

    assert byte_size(pcm) == 1_920
    refute_receive {:vxpipe_audio_playback, ^output, "turn-test", :started}

    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})
    assert_receive {:vxpipe_audio_playback, ^output, "turn-test", :started}

    assert :ok = push(output, connection_id, <<1, 0, 2, 0>>)
    assert :ok = finish(output)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{sequence_number: 1, timestamp: 960, payload: final_pcm}}

    assert byte_size(final_pcm) == 1_920
    assert binary_part(final_pcm, 0, 4) == <<1, 0, 2, 0>>
    refute_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, _duration}}

    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 960})
    assert_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, 40}}

    assert :ok = push(output, connection_id, :binary.copy(<<2>>, 1_920))

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{sequence_number: 2, timestamp: 1_920}}
  end

  test "backpressures a provider burst until acknowledged frames free bounded capacity" do
    {output, connection_id} = start_output(maximum_frames: 1)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})

    push = Task.async(fn -> push(output, connection_id, :binary.copy(<<0>>, 3 * 1_920)) end)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id, %PlaybackFrame{timestamp: 0}}

    assert Task.yield(push, 0) == nil
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 960}}

    assert Task.yield(push, 0) == nil
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 960})

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 1_920}}

    assert Task.await(push) == :ok
  end

  test "interrupt replaces the pipeline, drops queued audio, and returns confirmed duration" do
    {output, connection_id} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, first_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, first_id})

    assert :ok = push(output, connection_id, :binary.copy(<<0>>, 3 * 1_920))
    assert_receive {:test_audio_output_pipeline_push, ^first_id, %PlaybackFrame{timestamp: 0}}
    send(output, {:vxpipe_audio_output_pipeline_sent, first_id, 0})

    assert_receive {:test_audio_output_pipeline_push, ^first_id, %PlaybackFrame{timestamp: 960}}

    assert {:ok, 20} = interrupt(output)
    assert_receive {:test_audio_output_pipeline_stopped, ^first_id, _pipeline}
    assert_receive {:test_remote_playback_cleared, pipeline_options}
    assert pipeline_options[:test_observer] == self()
    assert_receive {:test_audio_output_pipeline_started, second_id, _pipeline, ^output}
    refute second_id == first_id

    send(output, {:vxpipe_audio_output_pipeline_sent, first_id, 960})
    refute_receive {:test_audio_output_pipeline_push, ^second_id, %PlaybackFrame{}}

    send(output, {:vxpipe_audio_output_pipeline_ready, second_id})
    assert :ok = push(output, connection_id, :binary.copy(<<0>>, 1_920))
    assert_receive {:test_audio_output_pipeline_push, ^second_id, %PlaybackFrame{timestamp: 0}}
  end

  test "records only PCM acknowledged by the telephony output pipeline" do
    {output, connection_id} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})

    handoff = recording_handoff(connection_id)
    assert {:error, :recording_not_bound} = AudioOutput.recording_binding(output)
    assert :ok = OutputSink.bind_recording(output, handoff)

    assert {:ok, resource, ^handoff, %{sample_rate: 48_000, channels: 1}} =
             AudioOutput.recording_binding(output)

    assert {:ok, ^resource, :ready} = AudioOutput.readiness(output)

    accepted = :binary.copy(<<1, 0>>, 960)
    queued = :binary.copy(<<2, 0>>, 960)
    assert :ok = push(output, connection_id, accepted <> queued)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id, %PlaybackFrame{timestamp: 0}}

    refute_receive {:vxpipe_recording_egress, ^handoff, %NormalizedFrame{}}
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})

    assert_receive {:vxpipe_recording_egress, ^handoff,
                    %NormalizedFrame{
                      source_participant_id: "agent-test",
                      connection_id: ^connection_id,
                      track_id: "agent-egress",
                      payload: ^accepted
                    }}

    :ok = EgressHandoff.release(handoff)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 960}}

    assert {:ok, 20} = interrupt(output)
    assert_receive {:test_audio_output_pipeline_stopped, ^pipeline_id, _pipeline}
    assert_receive {:test_remote_playback_cleared, _pipeline_options}
    assert_receive {:test_audio_output_pipeline_started, replacement_id, _pipeline, ^output}

    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 960})
    refute replacement_id == pipeline_id
    refute_receive {:vxpipe_recording_egress, ^handoff, %NormalizedFrame{}}
  end

  test "rejects mismatched identity and stops when the transport pipeline fails" do
    {output, connection_id} = start_output(maximum_frames: 1)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})

    wrong = %{frame(<<0, 0>>, connection_id) | connection_id: "connection-other"}
    assert {:error, :wrong_connection} = AudioOutput.push(output, wrong)

    monitor = Process.monitor(output)
    Process.exit(pipeline, :kill)

    assert_receive {:vxpipe_connection_unavailable, {:audio_output, :killed}}
    assert_receive {:DOWN, ^monitor, :process, ^output, :audio_output_unavailable}
  end

  test "private wait audio plays without entering the telephony recording handoff" do
    {output, connection} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    handoff = recording_handoff(connection)
    assert :ok = OutputSink.bind_recording(output, handoff)
    private = frame(:binary.copy(<<1, 0>>, 960), connection) |> Map.put(:audio_scope, :private)
    assert :ok = AudioOutput.push(output, private)
    assert :ok = finish(output)
    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id, %PlaybackFrame{timestamp: 0}}
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})
    assert_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, 20}}
    refute_receive {:vxpipe_recording_egress, ^handoff, _}
  end

  test "phase clearing drains the in-flight frame and preserves the codec and output clock" do
    {output, connection} = start_output(maximum_frames: 4)
    assert_receive {:test_audio_output_pipeline_started, pipeline_id, pipeline, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    assert :ok = push(output, connection, :binary.copy(<<1, 0>>, 3 * 960))
    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id, %PlaybackFrame{timestamp: 0}}
    request = :gen_server.send_request(output, :vxpipe_audio_output_clear)
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(request, 0)
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})
    assert {:reply, {:ok, 20}} = :gen_server.wait_response(request, 1_000)
    assert_receive {:test_remote_playback_cleared, _}
    refute_receive {:test_audio_output_pipeline_stopped, _, _}
    refute_receive {:test_audio_output_pipeline_started, _, _, _}
    assert :sys.get_state(output).pipeline_pid == pipeline
    assert :ok = push(output, connection, :binary.copy(<<2, 0>>, 960))

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{sequence_number: 1, timestamp: 960, payload: payload}}

    assert payload == :binary.copy(<<2, 0>>, 960)
  end

  test "remote drain waits for the exact provider mark and a clear supersedes it" do
    {output, connection} =
      start_output(playback_control: %{socket_owner: self(), stream_id: "stream"})

    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    assert :ok = push(output, connection, :binary.copy(<<1, 0>>, 960))
    assert :ok = finish(output)
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})
    assert_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, 20}}
    drain = :gen_server.send_request(output, :vxpipe_audio_output_drain)
    assert_receive {:vxpipe_playback_command, "stream", :drain, ^output, mark}
    assert :timeout = :gen_server.wait_response(drain, 0)
    send(output, {:vxpipe_playback_ack, make_ref(), :ok})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(drain, 0)
    clear = :gen_server.send_request(output, :vxpipe_audio_output_clear)
    assert_receive {:vxpipe_playback_command, "stream", :clear, ^output, cleared}
    assert {:reply, {:error, :cleared}} = :gen_server.wait_response(drain, 1_000)
    send(output, {:vxpipe_playback_ack, mark, :ok})
    _ = :sys.get_state(output)
    assert :timeout = :gen_server.wait_response(clear, 0)
    send(output, {:vxpipe_playback_ack, cleared, :ok})
    assert {:reply, {:ok, 0}} = :gen_server.wait_response(clear, 1_000)
    drain = :gen_server.send_request(output, :vxpipe_audio_output_drain)
    assert_receive {:vxpipe_playback_command, "stream", :drain, ^output, mark}
    send(output, {:vxpipe_playback_ack, mark, :ok})
    assert {:reply, :ok} = :gen_server.wait_response(drain, 1_000)
    assert :ok = push(output, connection, :binary.copy(<<2, 0>>, 960))

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 960}}
  end

  test "a missing remote playback acknowledgement fails closed" do
    {output, _connection} =
      start_output(playback_control: %{socket_owner: self(), stream_id: "stream"})

    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    monitor = Process.monitor(output)
    request = :gen_server.send_request(output, :vxpipe_audio_output_drain)
    assert_receive {:vxpipe_playback_command, "stream", :drain, ^output, mark}
    send(output, {:playback_ack_timeout, mark})
    assert {:reply, {:error, :playback_unavailable}} = :gen_server.wait_response(request, 1_000)
    assert_receive {:DOWN, ^monitor, :process, ^output, :audio_output_unavailable}
  end

  test "the arbiter keeps conversation closed until the remote drain is acknowledged" do
    alias Vxpipe.CallEngine.Media.OutputSink
    alias Vxpipe.Gateway.Media.OutputArbiter

    {native, connection} =
      start_output(playback_control: %{socket_owner: self(), stream_id: "stream"})

    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _, ^native}

    output =
      start_supervised!(
        {OutputArbiter,
         tenant_id: "tenant-test",
         room_id: "room-test",
         incarnation_id: "incarnation-test",
         participant_id: "caller-test",
         connection_id: connection,
         native_output: native,
         native_adapter: AudioOutput,
         owner: self()}
      )

    assert {:ok, _resource, :preparing} = OutputArbiter.readiness(output)
    send(native, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    assert {:ok, resource, :ready} = OutputArbiter.readiness(output)
    drain = :gen_server.send_request(output, :vxpipe_audio_output_drain)
    assert_receive {:vxpipe_playback_command, "stream", :drain, ^native, mark}
    assert {:ok, ^resource, :preparing} = OutputArbiter.readiness(output)
    assert {:error, :output_not_drained} = OutputSink.release(output, 0)

    assert {:error, :draining} =
             OutputSink.push(output, frame(:binary.copy(<<1, 0>>, 960), connection))

    send(native, {:vxpipe_playback_ack, mark, :ok})
    assert {:reply, :ok} = :gen_server.wait_response(drain, 1_000)
    assert :ok = OutputSink.release(output, 0)
    assert {:ok, ^resource, :ready} = OutputArbiter.readiness(output)
  end

  test "paces resumed output after idle without a catch-up burst or accumulated encoder delay" do
    clock = start_supervised!({Agent, fn -> 0 end})
    observer = self()

    {output, connection} =
      start_output(
        clock: fn -> Agent.get(clock, & &1) end,
        schedule: fn target, message, delay ->
          send(observer, {:paced, target, message, delay})
          make_ref()
        end
      )

    assert_receive {:test_audio_output_pipeline_started, pipeline_id, _, ^output}
    send(output, {:vxpipe_audio_output_pipeline_ready, pipeline_id})
    assert :ok = push(output, connection, :binary.copy(<<1, 0>>, 960))
    assert :ok = finish(output)
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 0})
    assert_receive {:paced, ^output, first_tick, 20}
    refute_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, _}}
    Agent.update(clock, fn _ -> 20 end)
    send(output, first_tick)
    assert_receive {:vxpipe_audio_playback, ^output, "turn-test", {:completed, 20}}

    Agent.update(clock, fn _ -> 20_000 end)
    assert :ok = push(output, connection, :binary.copy(<<2, 0>>, 3 * 960))

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 960}}

    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 960})
    assert_receive {:paced, ^output, second_tick, 20}
    send(output, first_tick)
    _ = :sys.get_state(output)

    refute_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 1920}}

    Agent.update(clock, fn _ -> 20_020 end)
    send(output, second_tick)

    assert_receive {:test_audio_output_pipeline_push, ^pipeline_id,
                    %PlaybackFrame{timestamp: 1920}}

    Agent.update(clock, fn _ -> 20_024 end)
    send(output, {:vxpipe_audio_output_pipeline_sent, pipeline_id, 1920})
    assert_receive {:paced, ^output, _third_tick, 16}
  end

  defp start_output(options) do
    connection_id = unique_id("connection")

    output =
      start_supervised!(
        {AudioOutput,
         [
           connection_id: connection_id,
           tenant_id: "tenant-test",
           room_id: "room-test",
           incarnation_id: "incarnation-test",
           participant_id: "caller-test",
           owner: self(),
           pipeline: Vxpipe.Gateway.TestAudioOutputPipeline,
           playback_clearer: Vxpipe.Gateway.TestPlaybackClearer,
           pipeline_supervisor: Vxpipe.Gateway.TestAudioOutputPipelineSupervisor,
           pipeline_options: [test_observer: self()]
         ] ++ options}
      )

    assert :ok = AudioOutput.start_pipeline(output)
    {output, connection_id}
  end

  defp push(output, connection_id, payload) do
    AudioOutput.push(output, frame(payload, connection_id))
  end

  defp finish(output), do: AudioOutput.finish(output, "turn-test", self())
  defp interrupt(output), do: AudioOutput.interrupt(output, "turn-test", self())

  defp frame(payload, connection_id) do
    %AudioOutputFrame{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      participant_id: "agent-test",
      connection_id: connection_id,
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

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
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
