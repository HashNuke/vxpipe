defmodule Vxpipe.CallEngine.Speech.ScopedRoomExperimentTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.SpeechExperiment.Call
  alias Vxpipe.CallEngine.SpeechExperiment.Recorder
  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}
  alias Vxpipe.CallEngine.{Event, TestAudioOutputSink, TestTransferConnection}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "production room recognizes independent PCM and confirms a complete synthesized reply" do
    context = Call.start(:scoped)
    result = Call.turn(context, :burst)
    assert result.counts == %{started: 1, final: 1, ended: 1, text: 1, completed: 1}
    assert result.transcript == "E"
    assert result.output == Call.pcm(20)
    assert result.metrics.first_audio_us >= 0
    assert result.metrics.playback_ack_us >= 0
    Call.stop(context)
  end

  test "replacement readiness contains only the selected speech generation" do
    alias Vxpipe.CallEngine.Capability.SpeechToText
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Resource

    context = Call.start(:scoped)
    assert {:ok, binding} = GenServer.call(context.connection, :vxpipe_connection_readiness)
    capability = :sys.get_state(context.attachment.media_ingress).capability
    assert {:ok, provider, :ready} = SpeechToText.readiness(capability)
    snapshot = context.room.incarnation_id |> Authority.whereis() |> Authority.snapshot()

    demand = %{audio_input?: true, room_output?: true, speech_to_text?: true}

    assert {:ok, resources, _track, []} =
             TestTransferConnection.prepare_candidate(
               binding,
               %{snapshot: snapshot},
               demand,
               speech_to_text: provider
             )

    assert Enum.map(resources, & &1.kind) == [
             :media_connection,
             :speech_to_text_ingress,
             :speech_to_text
           ]

    assert Enum.uniq_by(resources, &Resource.key/1) == resources
    Call.stop(context)
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
    old = state.session
    old_tree = Vxpipe.CallEngine.Speech.Session.tree(old)
    monitor = Process.monitor(old_tree)
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
    assert_receive {:DOWN, ^monitor, :process, ^old_tree, _}, 1_000
    :ok = Recorder.begin_turn(context.recorder)
    Call.push(context, Call.pcm(60))
    _ = :sys.get_state(context.attachment.media_ingress)
    _ = :sys.get_state(ingress.capability)
    assert :sys.get_state(ingress.capability).session == nil
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
    original = :sys.get_state(capability).session
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
    replacement = :sys.get_state(capability).pending_policy.state.session
    replacement_tree = Vxpipe.CallEngine.Speech.Session.tree(replacement)
    monitor = Process.monitor(replacement_tree)
    assert :ok = SpeechToText.discard_policy(capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement_tree, _}, 1_000
    assert :sys.get_state(capability).session == original
    assert Call.turn(context, :burst).transcript == "E"

    options =
      options
      |> Keyword.put(:attempt_id, "experiment-adopt")
      |> Keyword.put(:deadline_ms, System.monotonic_time(:millisecond) + 5_000)

    assert {:ok, next} = SpeechToText.prepare_policy(capability, candidate, options)
    [next_resource] = next.resources
    track = %{track_id: "morse", codec: :linear16, sample_rate: 16_000, channels: 1}
    assert :ok = Ingress.prepare_track(context.attachment.media_ingress, track, next_resource)

    next_collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: context.room.incarnation_id,
         attempt_id: "experiment-adopt",
         resources: [next_resource],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: {:experiment_adopt, Collector}
      )

    assert_receive {:vxpipe_readiness_changed, ^next_collector, %{status: :ready}}, 1_000

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    original_tree = Vxpipe.CallEngine.Speech.Session.tree(original)
    monitor = Process.monitor(original_tree)
    assert {:ok, _} = Vxpipe.CallEngine.join_participant(join)
    assert_receive {:DOWN, ^monitor, :process, ^original_tree, _}, 1_000
    refute :sys.get_state(capability).session == original
    :ok = Recorder.begin_turn(context.recorder)

    stale = %Vxpipe.CallEngine.Speech.Event{
      session: original,
      kind: :turn_ended,
      sequence: 999,
      turn_ref: make_ref(),
      text: "FORBIDDEN",
      endpointing: :provider_gap
    }

    send(capability, {:vxpipe_speech, stale})
    _ = :sys.get_state(capability)
    assert Recorder.snapshot(context.recorder).counts == %{}
    assert Call.turn(context, :burst).transcript == "E"
    Call.stop(context)
  end

  test "native allocation loss closes its connection tree while a same-room peer completes" do
    alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree
    alias Vxpipe.CallEngine.Speech.Session

    context = Call.start(:scoped)
    peer = attach_peer(context)
    ingress = context.attachment.media_ingress
    capability = :sys.get_state(ingress).capability
    connection_tree = ConnectionTree.parent(capability)
    capability_state = :sys.get_state(capability)
    allocation_tree = Session.tree(capability_state.session)

    allocation_monitor = Process.monitor(allocation_tree)
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    connection_tree_monitor = Process.monitor(connection_tree)

    Process.exit(allocation_tree, :kill)

    assert_receive {:DOWN, ^allocation_monitor, :process, ^allocation_tree, :killed}, 1_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :provider_failed}, 1_000

    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, _reason}, 1_000

    assert_receive {:DOWN, ^connection_tree_monitor, :process, ^connection_tree, :shutdown},
                   1_000

    assert Call.turn(peer, :burst).transcript == "E"
    Call.stop(context)
  end

  test "native capability-tree loss leaves a same-room peer recognizing" do
    alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree
    alias Vxpipe.CallEngine.Speech.CapabilityTree

    context = Call.start(:scoped)
    peer = attach_peer(context)
    ingress = context.attachment.media_ingress
    capability = :sys.get_state(ingress).capability
    connection_tree = ConnectionTree.parent(capability)

    scope =
      connection_tree
      |> Supervisor.which_children()
      |> Enum.find_value(fn
        {CapabilityTree, pid, :supervisor, _modules} -> pid
        _child -> nil
      end)

    assert is_pid(scope)

    scope_monitor = Process.monitor(scope)
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    connection_tree_monitor = Process.monitor(connection_tree)

    Process.exit(scope, :kill)

    assert_receive {:DOWN, ^scope_monitor, :process, ^scope, :killed}, 1_000
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _capability_reason}, 1_000
    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, _ingress_reason}, 1_000

    assert_receive {:DOWN, ^connection_tree_monitor, :process, ^connection_tree, :shutdown},
                   1_000

    assert Call.turn(peer, :burst).transcript == "E"
    Call.stop(context)
  end

  defp attach_peer(context) do
    connection_id = context.id <> "-peer"

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               incarnation_id: context.room.incarnation_id,
               participant_id: context.command.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    sink =
      start_supervised!(
        {TestAudioOutputSink, observer: context.recorder, block_output: false},
        id: {context.id, :peer_sink}
      )

    connection =
      start_supervised!(
        {TestTransferConnection,
         command: command,
         output: sink,
         observer: context.recorder,
         input_track: %{track_id: "morse", codec: :linear16, sample_rate: 16_000, channels: 1}},
        id: {context.id, :peer_connection}
      )

    assert {:ok, attachment} = GenServer.call(connection, :attach)

    :ok =
      GenServer.call(
        context.recorder,
        {:bind, Map.take(command, [:tenant_id, :room_id, :incarnation_id, :connection_id])}
      )

    %{context | command: command, connection: connection, attachment: attachment, sink: sink}
  end
end
