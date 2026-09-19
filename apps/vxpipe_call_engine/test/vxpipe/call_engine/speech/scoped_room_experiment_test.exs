defmodule Vxpipe.CallEngine.Speech.ScopedRoomExperimentTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.SpeechExperiment.Call
  alias Vxpipe.CallEngine.SpeechExperiment.Recorder
  alias Vxpipe.CallEngine.{Command.JoinParticipant, Event, TestAudioOutputSink}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "real room recognizes independent PCM and confirms a complete synthesized reply on both paths" do
    for path <- [:legacy, :scoped] do
      context = Call.start(path)
      result = Call.turn(context, :burst)
      assert result.counts == %{started: 1, final: 1, ended: 1, text: 1, completed: 1}
      assert result.transcript == "E"
      assert result.output == Call.pcm(20)
      assert result.metrics.first_audio_us >= 0
      assert result.metrics.playback_ack_us >= 0
      Call.stop(context)
    end
  end

  test "the connection advertises its configured PCM track during real policy preparation" do
    track = %{track_id: "morse", codec: :linear16, sample_rate: 16_000, channels: 1}
    demand = %{audio_input?: true, speech_to_text?: true}
    binding = %{resource: :fixture, input_track: track}

    assert {:ok, [:fixture], ^track} =
             Vxpipe.CallEngine.TestTransferConnection.prepare_binding(binding, nil, demand)
  end

  test "committed permission revocation closes recognition and denies later PCM" do
    context = Call.start(:scoped, observer: self())
    assert Call.turn(context, :burst).transcript == "E"
    ingress = :sys.get_state(context.attachment.media_ingress)
    state = :sys.get_state(ingress.capability)
    old = state.transport
    monitor = Process.monitor(old)
    restrictor = Map.fetch!(context.plan.participants, "restrictor")

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _} = Vxpipe.CallEngine.join_participant(join)
    assert_receive {:DOWN, ^monitor, :process, ^old, _}, 1_000
    :ok = Recorder.begin_turn(context.recorder)
    Call.push(context, Call.pcm(60))
    _ = :sys.get_state(context.attachment.media_ingress)
    _ = :sys.get_state(ingress.capability)
    assert :sys.get_state(ingress.capability).transport == nil
    assert Recorder.snapshot(context.recorder).counts == %{}
    assert DynamicSupervisor.count_children(context.scope).active == 1
    Call.stop(context)
  end

  test "PCM onset interrupts blocked output before turn end and permits a clean replacement" do
    context = Call.start(:scoped, block_output: true)
    :ok = Recorder.begin_turn(context.recorder)
    :ok = Recorder.tail(context.recorder)
    Call.push(context, Call.pcm(60))
    {_, first_frame} = Recorder.await(context.recorder, :audio)
    :ok = TestAudioOutputSink.playback_started(context.sink)
    <<dot::binary-size(1_920), gap::binary>> = Call.pcm(60)
    onset = System.monotonic_time(:microsecond)
    Call.push(context, dot)

    {interrupted_at, %Event.AgentTurnInterrupted{} = interrupted} =
      Recorder.await(context.recorder, :interrupted)

    {sink_at, _} = Recorder.await(context.recorder, :sink_interrupt)
    assert interrupted.correlation_id == first_frame.correlation_id
    assert sink_at <= interrupted_at
    assert interrupted_at - onset < 1_000_000
    assert Recorder.snapshot(context.recorder).counts.ended == 1
    assert :ok = GenServer.call(context.sink, {:block_output, false})
    :ok = Recorder.tail(context.recorder)
    Call.push(context, gap)
    result = Recorder.result(context.recorder)
    assert result.counts == %{started: 2, final: 2, ended: 2, text: 2, completed: 1}
    assert result.transcript == "E"
    assert result.output == Call.pcm(20)
    assert result.valid_correlations?
    snapshot = Recorder.snapshot(context.recorder)
    assert snapshot.counts.interrupted == 1
    refute snapshot.events.completed.correlation_id == first_frame.correlation_id
    Call.stop(context)
  end

  test "prepared replacement can be discarded and later adopted without leaking old transcripts" do
    alias Vxpipe.CallEngine.Capability.SpeechToText
    alias Vxpipe.CallEngine.Media.Ingress
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Collector

    context = Call.start(:scoped, restriction: %{save_transcripts: false})
    capability = :sys.get_state(context.attachment.media_ingress).capability
    original = :sys.get_state(capability).transport
    authority = Authority.whereis(context.room.incarnation_id)
    restrictor = Map.fetch!(context.plan.participants, "restrictor")
    snapshot = Authority.snapshot(authority)
    present = MapSet.put(snapshot.present_participant_ids, restrictor.participant_id)
    assert {:ok, candidate} = Authority.preview_presence(authority, present)

    options = [
      owner: self(),
      attempt_id: "experiment-prepare",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    assert {:ok, prepared} = SpeechToText.prepare_policy(capability, candidate, options)
    assert prepared.change == :replace
    [resource] = prepared.resources

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: context.room.incarnation_id,
         attempt_id: "experiment-prepare",
         resources: [resource],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    replacement = :sys.get_state(capability).pending_policy.state.transport
    monitor = Process.monitor(replacement)
    assert :ok = SpeechToText.discard_policy(capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _}, 1_000
    assert :sys.get_state(capability).transport == original
    assert Call.turn(context, :burst).transcript == "E"

    options = Keyword.put(options, :attempt_id, "experiment-adopt")
    assert {:ok, next} = SpeechToText.prepare_policy(capability, candidate, options)
    [next_resource] = next.resources
    track = %{track_id: "morse", codec: :linear16, sample_rate: 16_000, channels: 1}
    assert :ok = Ingress.prepare_track(context.attachment.media_ingress, track, next_resource)

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    monitor = Process.monitor(original)
    assert {:ok, _} = Vxpipe.CallEngine.join_participant(join)
    assert_receive {:DOWN, ^monitor, :process, ^original, _}, 1_000
    refute :sys.get_state(capability).transport == original
    :ok = Recorder.begin_turn(context.recorder)

    stale =
      JSON.encode!(%{
        "type" => "TurnInfo",
        "event" => "EndOfTurn",
        "sequence_id" => 999,
        "turn_index" => 0,
        "transcript" => "FORBIDDEN",
        "request_id" => "morse-local",
        "trigger" => "morse_end_gap"
      })

    send(capability, {:vxpipe_stt_transport, original, {:message, stale}})
    _ = :sys.get_state(capability)
    assert Recorder.snapshot(context.recorder).counts == %{}
    assert Call.turn(context, :burst).transcript == "E"
    Call.stop(context)
  end
end
