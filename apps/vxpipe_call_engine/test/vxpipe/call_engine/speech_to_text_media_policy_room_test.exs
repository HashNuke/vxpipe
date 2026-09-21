defmodule Vxpipe.CallEngine.SpeechToTextMediaPolicyRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    TestCallLifecycleTimer,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, JoinParticipant}
  alias Vxpipe.CallEngine.Event.ParticipantTranscription
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.CallEngine.Capability.SpeechToText
  alias Vxpipe.CallEngine.Capability.SpeechToText.ConnectionTree
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.Providers.Deepgram.Flux
  alias Vxpipe.Providers.Deepgram.STTSession, as: FluxSession
  alias Vxpipe.CallEngine.Speech.Channel

  test "prepares changed speech policy without replacing the live session until commit" do
    context = preparation_room()
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)
    ingress = context.attachment.media_ingress
    track = Map.take(preparation_frame(context, 1), [:track_id, :codec, :sample_rate, :channels])
    assert :ok = Ingress.prepare_track(ingress, track)
    assert {:ok, original_input, :ready} = Ingress.readiness(ingress)
    options = preparation_options()

    assert {:ok, prepared} = SpeechToText.prepare_policy(capability, candidate, options)
    assert prepared.change == :replace
    assert [resource] = prepared.resources
    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000

    assert {:error, :unavailable} =
             Ingress.prepare_track(ingress, track, %{resource | generation: make_ref()})

    assert {:error, :unavailable} =
             Ingress.readiness_resources(ingress, %{resource | configuration: <<0>>})

    assert {:ok, ^prepared} = SpeechToText.prepare_policy(capability, candidate, options)

    assert {:error, :preparation_conflict} =
             SpeechToText.prepare_policy(
               capability,
               candidate,
               Keyword.update!(options, :deadline_ms, &(&1 + 1_000))
             )

    refute_receive {:test_stt_transport_started, _, _}
    assert Authority.snapshot(context.authority) == candidate.base_snapshot
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    assert {:error, :policy_not_ready} = Enforcer.apply(capability, candidate.snapshot, 500)
    refute_transport_stopped(transport)

    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    assert_receive {:test_stt_audio, ^transport, <<1>>}
    refute_receive {:test_stt_audio, ^replacement, _audio}

    assert :ok = Ingress.prepare_track(ingress, track, resource)
    assert {:ok, [prepared_input, ^resource]} = Ingress.readiness_resources(ingress, resource)
    assert prepared_input.policy_interval == resource.policy_interval
    assert prepared_input.generation == original_input.generation
    assert {:ok, ^original_input, :ready} = Ingress.readiness(ingress)
    collector = collect([prepared_input, resource], context.room.incarnation_id)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing}}, 1_000
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    TestSpeechToTextTransport.deliver(replacement, turn_message("StartOfTurn", 1, "not admitted"))
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "not admitted"}}
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    assert {:ok, ^prepared_input, :ready} = Ingress.readiness_binding(prepared_input)
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert_transport_stopped(transport)
    refute_receive {:test_stt_transport_started, _, _}
    assert {:ok, committed, :ready} = SpeechToText.readiness(capability)
    assert committed.generation == resource.generation
    assert committed.policy_interval == resource.policy_interval
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    assert {:ok, ^prepared_input, :ready} = Ingress.readiness_binding(prepared_input)
    assert {:error, :stale_preparation} = SpeechToText.discard_policy(capability, prepared.token)
    assert Authority.snapshot(context.authority) == candidate.snapshot
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 2))
    assert_receive {:test_stt_audio, ^replacement, <<1>>}

    TestSpeechToTextTransport.deliver(
      replacement,
      turn_message("Update", 2, "still not admitted")
    )

    TestSpeechToTextTransport.deliver(replacement, turn_message("EndOfTurn", 3, "not admitted"))
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "not admitted"}}
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "still not admitted"}}

    TestSpeechToTextTransport.deliver(replacement, turn_message("StartOfTurn", 4, "admitted"))
    TestSpeechToTextTransport.deliver(replacement, turn_message("EndOfTurn", 5, "admitted"))
    assert_receive {:vxpipe_event, %ParticipantTranscription{text: "admitted"}}, 1_000
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "not admitted"}}
    refute_receive {:vxpipe_event, %ParticipantTranscription{text: "still not admitted"}}
  end

  test "discarding a prepared speech policy closes only its replacement session" do
    context = preparation_room()
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    ingress = context.attachment.media_ingress
    track = Map.take(preparation_frame(context, 1), [:track_id, :codec, :sample_rate, :channels])
    [resource] = prepared.resources
    assert :ok = Ingress.prepare_track(ingress, track, resource)
    assert {:ok, [prepared_input, ^resource]} = Ingress.readiness_resources(ingress, resource)
    monitor = Process.monitor(replacement)
    assert :ok = SpeechToText.discard_policy(capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    refute_transport_stopped(transport)
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))
    assert {:error, :unavailable} = Ingress.readiness_binding(prepared_input)
    assert {:error, :unavailable} = Ingress.prepare_track(ingress, track, resource)
    assert Authority.snapshot(context.authority) == candidate.base_snapshot
  end

  test "preparing an unrelated policy retains the exact speech session and resource" do
    context = preparation_room(restriction: %{record_audio: false})
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)
    ingress = context.attachment.media_ingress
    track = Map.take(preparation_frame(context, 1), [:track_id, :codec, :sample_rate, :channels])
    assert :ok = Ingress.prepare_track(ingress, track)
    assert {:ok, original_input, :ready} = Ingress.readiness(ingress)

    assert {:ok, %{change: :retain, resources: [^original]}} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert :ok = Ingress.prepare_track(ingress, track, original)
    assert {:ok, [^original_input, ^original]} = Ingress.readiness_resources(ingress, original)

    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    assert {:ok, [^original_input, ^original]} = Ingress.readiness_resources(ingress, original)
    refute_receive {:test_stt_transport_started, _, _}
    refute_transport_stopped(transport)
  end

  test "preparing a speech denial keeps the current session until commit" do
    context = preparation_room(restriction: %{transcript_routes: %{}, save_transcripts: false})
    %{capability: capability, transport: transport, candidate: candidate} = context
    assert {:ok, original, :ready} = SpeechToText.readiness(capability)

    assert {:ok, %{change: :disable, resources: []}} =
             SpeechToText.prepare_policy(capability, candidate, preparation_options())

    assert {:ok, ^original, :ready} = SpeechToText.readiness(capability)
    refute_transport_stopped(transport)
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert_transport_stopped(transport)
    refute_receive {:test_stt_transport_started, _, _}
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    refute_receive {:test_stt_audio, _, _}
  end

  test "prepares a future input route while the installed policy still denies microphone delivery" do
    context = preparation_room(restriction: %{transcript_routes: %{}, save_transcripts: false})
    ingress = context.attachment.media_ingress
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    transport = context.transport
    assert_transport_stopped(transport)
    base = Authority.snapshot(context.authority)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.delete(base.present_participant_ids, context.join.participant_id)
             )

    assert {:ok, %{resources: [provider]}} =
             SpeechToText.prepare_policy(context.capability, candidate, preparation_options())

    assert_receive {:test_stt_transport_started, replacement, _connection}
    track = Map.take(preparation_frame(context, 1), [:track_id, :codec, :sample_rate, :channels])

    assert {:error, :track_already_prepared} =
             Ingress.prepare_track(ingress, %{track | codec: :linear16}, provider)

    assert :ok = Ingress.prepare_track(ingress, track, provider)
    assert {:ok, [input, ^provider]} = Ingress.readiness_resources(ingress, provider)
    collector = collect([input, provider], context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, _live_input, :preparing} = Ingress.readiness(ingress)
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    refute_receive {:test_stt_audio, ^replacement, _audio}
    assert Authority.snapshot(context.authority) == base

    assert {:ok, installed} = Authority.leave(context.authority, context.join.participant_id)
    assert installed == candidate.snapshot
    assert {:ok, ^input, :ready} = Ingress.readiness_binding(input)
    frame = %{preparation_frame(context, 2) | payload: <<2>>}
    assert :ok = CallEngine.push_audio(context.attachment, frame)
    assert_receive {:test_stt_audio, ^replacement, <<2>>}
    refute_receive {:test_stt_audio, ^replacement, <<1>>}
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "preparation owner loss cancels only its pending speech session" do
    context = preparation_room()
    owner = start_supervised!({Agent, fn -> :owner end}, id: :preparation_owner)
    options = Keyword.put(preparation_options(), :owner, owner)
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    monitor = Process.monitor(replacement)
    stop_supervised!(:preparation_owner)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :failed} = SpeechToText.readiness_binding(hd(prepared.resources))

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.capability, context.candidate.snapshot, 500)
  end

  test "an unrelated membership revision retains and rebinds an already ready replacement" do
    context = preparation_room()
    options = preparation_options()
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    ingress = context.attachment.media_ingress
    track = Map.take(preparation_frame(context, 1), [:track_id, :codec, :sample_rate, :channels])
    [provider] = prepared.resources
    assert :ok = Ingress.prepare_track(ingress, track, provider)

    assert {:ok, [prepared_input, ^provider] = resources} =
             Ingress.readiness_resources(ingress, provider)

    collector = collect(resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    observer = Map.fetch!(context.plan.participants, "observer")

    join = %{
      context.join
      | id: Vxpipe.CallEngine.Id.generate(:command),
        participant_id: observer.participant_id
    }

    assert {:ok, _participant} = CallEngine.join_participant(join)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))
    assert {:error, :unavailable} = Ingress.readiness_binding(prepared_input)
    current = Authority.snapshot(context.authority)
    destination = context.join.participant_id

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, destination)
             )

    assert {:ok, rebound} = SpeechToText.prepare_policy(context.capability, candidate, options)
    assert rebound.token == prepared.token
    before = hd(prepared.resources)
    after_rebase = hd(rebound.resources)
    assert after_rebase.generation == before.generation
    assert after_rebase.configuration == before.configuration
    assert after_rebase.policy_interval != before.policy_interval
    assert {:ok, ^after_rebase, :ready} = SpeechToText.readiness_binding(after_rebase)

    assert {:ok, [rebound_input, ^after_rebase]} =
             Ingress.readiness_resources(ingress, after_rebase)

    assert rebound_input.generation == prepared_input.generation
    assert rebound_input.configuration == prepared_input.configuration
    assert rebound_input.policy_interval == after_rebase.policy_interval
    assert {:ok, ^rebound_input, :ready} = Ingress.readiness_binding(rebound_input)
    refute_receive {:test_stt_transport_started, _, _}
    assert {:ok, _participant} = CallEngine.join_participant(context.join)
    assert {:ok, committed, :ready} = SpeechToText.readiness(context.capability)
    assert committed.generation == before.generation
    assert {:ok, ^rebound_input, :ready} = Ingress.readiness_binding(rebound_input)
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    assert_receive {:test_stt_audio, ^replacement, <<1>>}
  end

  test "preparation deadline closes the pending transport and rejects commit" do
    context = preparation_room()

    options =
      Keyword.put(
        preparation_options(),
        :deadline_ms,
        System.monotonic_time(:millisecond) + 1_000
      )

    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}
    monitor = Process.monitor(replacement)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_500
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:error, :unavailable} = SpeechToText.readiness_binding(hd(prepared.resources))

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.capability, context.candidate.snapshot, 500)
  end

  test "prepared session adoption cannot commit after its policy deadline" do
    context = preparation_room()
    deadline = System.monotonic_time(:millisecond) + 2_000
    options = Keyword.put(preparation_options(), :deadline_ms, deadline)
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    collector = collect(prepared.resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    pending = :sys.get_state(context.capability).pending_policy.state.session
    channel = GenServer.whereis(Channel.address(pending))
    :ok = :sys.suspend(channel)

    apply =
      Task.async(fn ->
        Enforcer.apply(context.capability, context.candidate.snapshot, 4_000)
      end)

    try do
      assert_channel_has_adoption(channel, 1_000)
      wait_ms = max(deadline - now() + 20, 1)
      timer = Process.send_after(self(), :policy_deadline_elapsed, wait_ms)
      assert_receive :policy_deadline_elapsed, wait_ms + 500
      Process.cancel_timer(timer)
      :ok = :sys.resume(channel)

      assert {:error, :policy_not_ready} = Task.await(apply, 1_000)
      assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    after
      try do
        :sys.resume(channel)
      catch
        :exit, _reason -> :ok
      end

      Task.shutdown(apply, :brutal_kill)
    end
  end

  test "prepared session adoption cannot commit after its owner exits" do
    context = preparation_room()
    owner = start_supervised!({Agent, fn -> :preparing end}, id: :held_adoption_owner)
    options = Keyword.put(preparation_options(), :owner, owner)
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    collector = collect(prepared.resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    pending = :sys.get_state(context.capability).pending_policy.state.session
    channel = GenServer.whereis(Channel.address(pending))
    :ok = :sys.suspend(channel)

    apply =
      Task.async(fn ->
        Enforcer.apply(context.capability, context.candidate.snapshot, 4_000)
      end)

    try do
      assert_channel_has_adoption(channel, 1_000)
      stop_supervised!(:held_adoption_owner)
      :ok = :sys.resume(channel)

      assert {:error, :policy_not_ready} = Task.await(apply, 1_000)
      assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    after
      try do
        :sys.resume(channel)
      catch
        :exit, _reason -> :ok
      end

      Task.shutdown(apply, :brutal_kill)
    end
  end

  test "policy commit waits only for old session retirement acceptance" do
    context = preparation_room()
    deadline = now() + 4_000
    options = Keyword.put(preparation_options(), :deadline_ms, deadline)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000
    collector = collect(prepared.resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(replacement, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000

    source = :sys.get_state(context.capability).session
    source_channel = GenServer.whereis(Channel.address(source))
    :ok = :sys.suspend(source_channel)

    apply =
      Task.async(fn ->
        Enforcer.apply(context.capability, context.candidate.snapshot, 3_000)
      end)

    try do
      assert {:ok, :ok} = Task.yield(apply, 500)
    after
      try do
        :sys.resume(source_channel)
      catch
        :exit, _reason -> :ok
      end

      Task.shutdown(apply, :brutal_kill)
    end
  end

  test "pending provider failure leaves the source ready and a new attempt rejects old cleanup" do
    context = preparation_room()
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, first} =
             SpeechToText.prepare_policy(
               context.capability,
               context.candidate,
               preparation_options()
             )

    assert_receive {:test_stt_transport_started, replacement, _connection}
    collector = collect(first.resources, context.room.incarnation_id)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing}}, 1_000
    monitor = Process.monitor(replacement)
    TestSpeechToTextTransport.disconnect(replacement, :closed)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :failed}}, 1_000
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :failed} = SpeechToText.readiness_binding(hd(first.resources))
    assert :ok = SpeechToText.discard_policy(context.capability, first.token)
    options = Keyword.put(preparation_options(), :attempt_id, "next-policy-attempt")

    assert {:ok, second} =
             SpeechToText.prepare_policy(context.capability, context.candidate, options)

    assert_receive {:test_stt_transport_started, next, _connection}
    assert second.token != first.token

    assert {:error, :stale_preparation} =
             SpeechToText.discard_policy(context.capability, first.token)

    send(context.capability, {:stt_policy_expired, first.token})
    assert {:ok, _resource, :preparing} = SpeechToText.readiness_binding(hd(second.resources))
    monitor = Process.monitor(next)
    assert :ok = SpeechToText.discard_policy(context.capability, second.token)
    assert_receive {:DOWN, ^monitor, :process, ^next, _reason}, 1_000
  end

  test "rejects a candidate from another authority even when its policy snapshot matches" do
    context = preparation_room()

    other =
      start_supervised!(
        Supervisor.child_spec(
          {Authority, plan: context.plan, incarnation_id: "foreign-policy", register: false},
          significant: false
        )
      )

    assert {:ok, _snapshot} = Authority.admit(other, context.caller.participant_id)
    receiver = Map.fetch!(context.plan.participants, context.plan.entry_receiver)
    assert {:ok, _snapshot} = Authority.admit(other, receiver.participant_id)

    assert {:ok, foreign} =
             Authority.preview_presence(other, context.candidate.snapshot.present_participant_ids)

    assert foreign.base_snapshot == context.candidate.base_snapshot

    assert {:error, :wrong_policy_authority} =
             SpeechToText.prepare_policy(context.capability, foreign, preparation_options())

    refute_receive {:test_stt_transport_started, _, _}
  end

  test "a blocked replacement constructor leaves the capability responsive and is cancelled" do
    observer = self()
    calls = :atomics.new(1, [])

    before_connect = fn ->
      if :atomics.add_get(calls, 1, 1) == 2 do
        send(observer, {:replacement_connecting, self()})

        receive do
          :continue -> :ok
        end
      end
    end

    context = preparation_room(transport_options: [before_connect: before_connect])
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(
               context.capability,
               context.candidate,
               preparation_options()
             )

    assert_receive {:replacement_connecting, connector}
    monitor = Process.monitor(connector)
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    assert {:ok, _resource, :preparing} = SpeechToText.readiness_binding(hd(prepared.resources))
    assert :ok = SpeechToText.discard_policy(context.capability, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^connector, _reason}, 1_000
  end

  test "a privately initialized speech pair prepares one provider session and keeps input closed through adoption" do
    context = preparation_room()
    assert {:ok, original_source, :ready} = SpeechToText.readiness(context.capability)
    owner = start_supervised!({Agent, fn -> :phase end}, id: :adopted_private_phase)
    options = Keyword.put(preparation_options(), :owner, owner)
    private = prepare_private_speech(context, options)

    %{capability: capability, ingress: ingress, resource: resource, transport: transport} =
      private

    frame = private_frame(context, private, 1)
    track = Map.take(frame, [:track_id, :codec, :sample_rate, :channels])
    assert :ok = Ingress.prepare_track(ingress, track, resource)
    assert {:ok, resources} = Ingress.readiness_resources(ingress, resource)
    collector = collect(resources, context.room.incarnation_id)
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert :ok = Ingress.push(ingress, private_frame(context, private, 1))
    refute_receive {:test_stt_audio, ^transport, _}
    assert Authority.snapshot(context.authority) == private.candidate.base_snapshot
    prepared = private.prepared

    assert {:ok, ^prepared} =
             SpeechToText.prepare_policy(capability, private.candidate, private.options)

    refute_receive {:test_stt_transport_started, _, _}

    assert {:ok, adopted} =
             Authority.commit_candidate(
               context.authority,
               private.candidate,
               Keyword.fetch!(private.options, :deadline_ms),
               [capability, ingress]
             )

    assert adopted == private.candidate.snapshot
    stop_supervised!(:adopted_private_phase)
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    assert :ok = Ingress.push(ingress, private_frame(context, private, 2))
    refute_receive {:test_stt_audio, ^transport, _}
    assert :ok = Ingress.open(ingress)
    assert :ok = Ingress.push(ingress, private_frame(context, private, 3))
    assert_receive {:test_stt_audio, ^transport, <<1>>}
    refute_receive {:test_stt_transport_started, _, _}
    assert {:ok, ^original_source, :ready} = SpeechToText.readiness(context.capability)
  end

  test "discarding a private speech pair preserves the source and permits another preparation" do
    context = preparation_room()
    assert {:ok, original_source, :ready} = SpeechToText.readiness(context.capability)
    private = prepare_private_speech(context)
    transport = private.transport
    TestSpeechToTextTransport.deliver(transport, connected_message())
    collector = collect([private.resource], context.room.incarnation_id)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    transport_monitor = Process.monitor(transport)
    assert :ok = SpeechToText.discard_policy(private.capability, private.prepared.token)
    assert_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}, 1_000
    stop_private_speech(context, private)
    assert Authority.snapshot(context.authority) == private.candidate.base_snapshot
    assert {:ok, ^original_source, :ready} = SpeechToText.readiness(context.capability)
    source_transport = context.transport
    assert :ok = CallEngine.push_audio(context.attachment, preparation_frame(context, 1))
    assert_receive {:test_stt_audio, ^source_transport, <<1>>}
    retry = prepare_private_speech(context)
    assert retry.transport != transport
    stop_private_speech(context, retry)
    assert Authority.snapshot(context.authority) == private.candidate.base_snapshot
  end

  test "private allocation owner loss stops the pair before provider preparation" do
    context = preparation_room()
    assert {:ok, original, :ready} = SpeechToText.readiness(context.capability)
    owner = start_supervised!({Agent, fn -> :phase end}, id: :private_phase)
    options = Keyword.put(preparation_options(), :owner, owner)
    private = start_private_speech(context, options)
    capability = private.capability
    ingress = private.ingress
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    stop_supervised!(:private_phase)
    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :shutdown}, 1_000
    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, :capability_unavailable}, 1_000
    assert Authority.snapshot(context.authority) == private.base
    assert {:ok, ^original, :ready} = SpeechToText.readiness(context.capability)
    refute_receive {:test_stt_transport_started, _, _}
  end

  test "private allocation deadline closes the pair and its unacknowledged provider" do
    context = preparation_room()

    options =
      Keyword.put(
        preparation_options(),
        :deadline_ms,
        System.monotonic_time(:millisecond) + 2_000
      )

    private = prepare_private_speech(context, options)
    capability = private.capability
    ingress = private.ingress
    transport = private.transport
    monitors = Enum.map([capability, ingress, transport], &{&1, Process.monitor(&1)})

    for {process, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^process, _reason}, 3_000
    end

    assert Authority.snapshot(context.authority) == private.candidate.base_snapshot
    assert {:ok, _source, :ready} = SpeechToText.readiness(context.capability)
  end

  test "connection tree teardown does not depend on capability responsiveness" do
    context = preparation_room()
    capability = context.capability
    ingress = context.attachment.media_ingress
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)
    :ok = :sys.suspend(capability)

    stop =
      Task.async(fn ->
        CallEngine.RoomCapabilitySupervisor.stop_speech_to_text(
          context.room.incarnation_id,
          capability,
          ingress
        )
      end)

    try do
      assert_receive {:DOWN, ^capability_monitor, :process, ^capability, _capability_reason}, 500
      assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, _ingress_reason}, 500
      assert :ok = Task.await(stop, 500)
    after
      try do
        :sys.resume(capability)
      catch
        :exit, _reason -> :ok
      end

      Task.shutdown(stop, :brutal_kill)
    end
  end

  test "connection tree records the exact parent for its capability pid" do
    context = preparation_room()
    capability = context.capability
    tree = ConnectionTree.parent(capability)

    assert is_pid(tree)

    assert [{^tree, nil}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {ConnectionTree, :parent, capability}
             )
  end

  test "private allocation requires its original phase and prepared session before admission" do
    context = preparation_room()
    options = preparation_options()
    private = start_private_speech(context, options)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(private.base.present_participant_ids, private.observer.participant_id)
             )

    assert {:error, :invalid_preparation} =
             SpeechToText.prepare_policy(
               private.capability,
               candidate,
               Keyword.put(options, :attempt_id, "another-phase")
             )

    assert {:error, :invalid_preparation} =
             SpeechToText.prepare_policy(
               private.capability,
               candidate,
               Keyword.update!(options, :deadline_ms, &(&1 + 1_000))
             )

    assert {:error, :policy_not_prepared} =
             Enforcer.apply(private.capability, candidate.snapshot, 1_000)

    refute_receive {:test_stt_transport_started, _, _}
    stop_private_speech(context, private)
    assert Authority.snapshot(context.authority) == private.base
  end

  test "a private allocation without future speech demand cannot become a live enforcer" do
    context = preparation_room(restriction: %{save_transcripts: false, transcript_routes: %{}})
    options = preparation_options()
    private = start_private_speech(context, options)
    restrictor = Map.fetch!(context.plan.participants, "restrictor")

    present =
      private.base.present_participant_ids
      |> MapSet.put(private.observer.participant_id)
      |> MapSet.put(restrictor.participant_id)

    assert {:ok, candidate} = Authority.preview_presence(context.authority, present)

    assert {:ok, %{resources: []}} =
             SpeechToText.prepare_policy(private.capability, candidate, options)

    assert {:error, :policy_not_prepared} =
             Enforcer.apply(private.capability, candidate.snapshot, 1_000)

    refute_receive {:test_stt_transport_started, _, _}
    stop_private_speech(context, private)
    assert Authority.snapshot(context.authority) == private.base
  end

  test "unrelated membership refresh retains the privately prepared provider session" do
    context = preparation_room(restriction: %{record_audio: false})
    private = prepare_private_speech(context, preparation_options())
    transport = private.transport
    transport_monitor = Process.monitor(transport)
    TestSpeechToTextTransport.deliver(transport, connected_message())
    collector = collect([private.resource], context.room.incarnation_id)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    restrictor = Map.fetch!(context.plan.participants, "restrictor")
    assert {:ok, base} = Authority.admit(context.authority, restrictor.participant_id)
    assert :ok = Enforcer.apply(private.ingress, base, 1_000)
    assert :ok = Enforcer.apply(private.capability, base, 1_000)
    refute_receive {:DOWN, ^transport_monitor, :process, ^transport, _reason}

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(base.present_participant_ids, private.observer.participant_id)
             )

    assert {:ok, prepared} =
             SpeechToText.prepare_policy(private.capability, candidate, private.options)

    assert prepared.token == private.prepared.token
    assert [resource] = prepared.resources
    assert resource.generation == private.resource.generation
    assert resource.policy_interval != private.resource.policy_interval
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
    refute_receive {:test_stt_transport_started, _, _}

    assert {:ok, adopted} =
             Authority.commit_candidate(
               context.authority,
               candidate,
               Keyword.fetch!(private.options, :deadline_ms),
               [private.capability, private.ingress]
             )

    assert adopted == candidate.snapshot
    assert {:ok, ^resource, :ready} = SpeechToText.readiness_binding(resource)
  end

  defp prepare_private_speech(context, scoped_options \\ nil) do
    private = start_private_speech(context, scoped_options)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(private.base.present_participant_ids, private.observer.participant_id)
             )

    options = scoped_options || preparation_options()
    assert {:ok, prepared} = SpeechToText.prepare_policy(private.capability, candidate, options)
    assert [resource] = prepared.resources
    assert_receive {:test_stt_transport_started, transport, _connection}, 1_000

    Map.merge(private, %{
      candidate: candidate,
      prepared: prepared,
      resource: resource,
      transport: transport,
      options: options
    })
  end

  defp start_private_speech(context, options) do
    observer = Map.fetch!(context.plan.participants, "observer")
    base = Authority.snapshot(context.authority)
    connection_id = unique_id("private-speech")

    [{room_authority, _}] =
      Registry.lookup(CallEngine.RoomRegistry, {context.plan.tenant_id, context.plan.room_id})

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: context.plan.tenant_id,
               actor_id: context.plan.actor_id,
               room_id: context.plan.room_id,
               incarnation_id: context.room.incarnation_id,
               participant_id: observer.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, provider} =
             Flux.new(
               api_key: "private-speech-fixture",
               model: "flux-general-en",
               encoding: :opus,
               sample_rate: 48_000
             )

    ingress_options = [
      input_admission: :closed,
      maximum_age_ms: 1_000,
      maximum_bytes: 65_536,
      maximum_frames: 20,
      maximum_consecutive_overflows: 3
    ]

    assert {:ok, capability, ingress} =
             CallEngine.RoomCapabilitySupervisor.start_speech_to_text(
               context.room.incarnation_id,
               room_authority,
               command,
               {FluxSession,
                model: provider.model,
                encoding: provider.encoding,
                sample_rate: provider.sample_rate},
               ingress_options,
               nil,
               private_initialization(base, options) ++
                 [
                   provider_private: [
                     config: provider,
                     wire_module: TestSpeechToTextTransport,
                     wire_options: [observer: self()]
                   ]
                 ]
             )

    assert :ok = Enforcer.apply(ingress, base, 1_000)
    assert :ok = Enforcer.apply(capability, base, 1_000)
    refute_receive {:test_stt_transport_started, _, _}

    %{
      capability: capability,
      ingress: ingress,
      base: base,
      observer: observer,
      connection_id: connection_id
    }
  end

  defp private_initialization(base, nil), do: [initial_policy: base]
  defp private_initialization(base, options), do: [initial_policy: base, preparation: options]

  defp stop_private_speech(context, private) do
    capability = private.capability
    ingress = private.ingress
    capability_monitor = Process.monitor(capability)
    ingress_monitor = Process.monitor(ingress)

    assert :ok =
             CallEngine.RoomCapabilitySupervisor.stop_speech_to_text(
               context.room.incarnation_id,
               capability,
               ingress
             )

    assert_receive {:DOWN, ^capability_monitor, :process, ^capability, :shutdown}, 1_000
    assert_receive {:DOWN, ^ingress_monitor, :process, ^ingress, :shutdown}, 1_000
  end

  defp private_frame(context, private, sequence),
    do: audio_frame(context.plan, context.room, private.observer, private.connection_id, sequence)

  defp preparation_room(options \\ []) do
    configure_speech_to_text(Keyword.get(options, :transport_options, []))

    plan =
      compile_plan(
        media_policy: %{save_transcripts: true},
        restrictor?: true,
        observer?: true,
        restriction: Keyword.get(options, :restriction, %{save_transcripts: false})
      )

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    on_exit(fn ->
      try do
        case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
          [{authority, _value}] -> GenServer.stop(authority, :shutdown)
          [] -> :ok
        end
      catch
        :exit, {:noproc, _call} -> :ok
      end
    end)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    restrictor = Map.fetch!(plan.participants, "restrictor")
    connection_id = unique_id("preparation")
    attachment = attach(plan, room, caller, connection_id)
    assert_receive {:test_stt_transport_started, transport, _connection}
    _receiver = attach(plan, room, receiver, unique_id("receiver"))
    assert {:ok, resources} = Ingress.readiness_resources(attachment.media_ingress)
    resource = Enum.find(resources, &(&1.kind == :speech_to_text))
    collector = collect([resource], room.incarnation_id)
    TestSpeechToTextTransport.deliver(transport, connected_message())
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)
    authority = Authority.whereis(room.incarnation_id)
    base = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, restrictor.participant_id)
             )

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 10, :second)
             )

    %{
      plan: plan,
      room: room,
      caller: caller,
      connection_id: connection_id,
      attachment: attachment,
      capability: resource.instance,
      transport: transport,
      candidate: candidate,
      authority: authority,
      join: join
    }
  end

  defp preparation_options,
    do: [
      owner: self(),
      attempt_id: "policy-preparation",
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

  defp assert_channel_has_adoption(channel, timeout) do
    deadline = now() + timeout
    await_channel_adoption(channel, deadline)
  end

  defp await_channel_adoption(channel, deadline) do
    {:messages, messages} = Process.info(channel, :messages)

    adoption? =
      Enum.any?(messages, fn
        {:"$gen_call", _from, {:command, _allocation, _deadline, {:adopt, _consumer, _command}}} ->
          true

        _message ->
          false
      end)

    if adoption? do
      :ok
    else
      if now() < deadline do
        receive do
        after
          1 -> await_channel_adoption(channel, deadline)
        end
      else
        flunk("adoption command did not reach the held channel")
      end
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp preparation_frame(context, sequence),
    do: audio_frame(context.plan, context.room, context.caller, context.connection_id, sequence)

  defp collect(resources, incarnation) do
    start_supervised!(
      {Collector,
       owner: self(),
       incarnation_id: incarnation,
       attempt_id: "policy-preparation",
       resources: resources,
       deadline_ms: System.monotonic_time(:millisecond) + 5_000},
      id: make_ref()
    )
  end

  defp connected_message,
    do: ~s({"type":"Connected","request_id":"prepared-speech","sequence_id":0})

  test "planned room binds STT to its current media policy before accepting audio" do
    configure_speech_to_text()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    attachment = attach(plan, room, caller, "conn-stt-policy")

    refute_receive {:test_stt_transport_started, _, _}

    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(plan, room, caller, "conn-stt-policy", 1)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  test "keeps live-only STT running and stops it when no consumer remains" do
    configure_speech_to_text()

    plan =
      compile_plan(
        media_policy: %{
          transcript_routes: %{"caller" => ["receiver"]},
          save_transcripts: false
        },
        restrictor?: true
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    restrictor = Map.fetch!(plan.participants, "restrictor")

    assert {:ok, room} =
             Vxpipe.CallEngine.TestCallStartup.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    caller_attachment = attach(plan, room, caller, "conn-live-caller")
    assert_receive {:test_stt_transport_started, transport, _connection}
    refute_transport_stopped(transport)

    _receiver_attachment = attach(plan, room, receiver, "conn-live-receiver")
    TestSpeechToTextTransport.deliver(transport, connected_message())
    Vxpipe.CallEngine.TestCallStartup.await_ready(plan.room_id)
    assert CallEngine.RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :open

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 1)
             )

    assert_receive {:test_stt_audio, ^transport, <<1>>}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("StartOfTurn", 1, "live only")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      participant_id: caller_participant_id,
                      text: "live only",
                      final: false
                    }}

    assert caller_participant_id == caller.participant_id

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: restrictor.participant_id,
               role: :human,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _participant} = CallEngine.join_participant(join)
    assert_transport_stopped(transport)

    assert :ok =
             CallEngine.push_audio(
               caller_attachment,
               audio_frame(plan, room, caller, "conn-live-caller", 2)
             )

    refute_receive {:test_stt_audio, _transport, _audio}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)
  end

  defp compile_plan(options \\ []) do
    media_policy =
      Keyword.get(options, :media_policy, %{transcript_routes: %{}, save_transcripts: false})

    participants = %{
      "caller" =>
        human_participant(%{
          speech_to_text: %{
            provider: "deepgram",
            model: "flux-general-multi",
            options: %{encoding: "opus", sample_rate: 48_000}
          }
        }),
      "receiver" => human_participant(%{})
    }

    participants =
      if Keyword.get(options, :observer?, false),
        do: Map.put(participants, "observer", human_participant(%{})),
        else: participants

    participants =
      if Keyword.get(options, :restrictor?, false) do
        Map.put(
          participants,
          "restrictor",
          Map.put(
            human_participant(%{}),
            :while_present,
            Keyword.get(options, :restriction, %{
              transcript_routes: %{},
              save_transcripts: false
            })
          )
        )
      else
        participants
      end

    input = %{
      schema_version: CallSpec.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      media_policy: media_policy,
      call_variables: %{sections: %{}},
      participants: participants,
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: "stt-policy-room", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "stt-policy-room", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-stt-policy",
               actor_id: "actor-stt-policy",
               call_id: unique_id("call-stt-policy"),
               room_id: unique_id("room-stt-policy")
             )

    registries = %{
      host_tools: %{}
    }

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries)
    plan
  end

  defp human_participant(capabilities) do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: capabilities
    }
  end

  defp attach(plan, room, participant, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, attachment} =
             Vxpipe.CallEngine.TestTransferConnection.attach(command, nil,
               input_track: %{
                 track_id: "track-stt-policy",
                 codec: :opus,
                 sample_rate: 48_000,
                 channels: 1
               }
             )

    attachment
  end

  defp audio_frame(plan, room, participant, connection_id, sequence_number) do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: connection_id,
      track_id: "track-stt-policy",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      payload: <<1>>,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp turn_message(event, sequence, transcript) do
    JSON.encode!(%{
      "type" => "TurnInfo",
      "request_id" => "request-live-only",
      "sequence_id" => sequence,
      "event" => event,
      "trigger" => "model",
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    })
  end

  defp assert_transport_stopped(transport) do
    monitor = Process.monitor(transport)
    assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 1_000
  end

  defp refute_transport_stopped(transport) do
    monitor = Process.monitor(transport)
    refute_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 100
    Process.demonitor(monitor, [:flush])
  end

  defp configure_speech_to_text(transport_options \\ []) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      providers: %{
        FluxSession => [
          enabled: true,
          wire_module: TestSpeechToTextTransport,
          wire_options: [observer: self()] ++ transport_options,
          media_ingress: [
            maximum_frames: 8,
            maximum_bytes: 1024,
            maximum_age_ms: 1_000,
            maximum_consecutive_overflows: 2
          ]
        ]
      }
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :speech_to_text, speech_to_text)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
