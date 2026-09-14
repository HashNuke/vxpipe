defmodule Vxpipe.CallEngine.RoomRecordingPolicyPreparationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    RoomMixer,
    RoomRecording,
    TestRecordingWriter
  }

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer, Snapshot}

  test "prepares future writers privately and preserves live sequence numbers through adoption" do
    context = start_context()
    assert {:ok, live, :ready} = RoomRecording.readiness(context.recording)

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    joining_track = track(context.joining)
    assert_receive {:test_recording_writer_opened, source, source, %{mode: ^joining_track}}
    refute source == context.recording
    assert {:ok, ^live, :ready} = RoomRecording.readiness(context.recording)

    assert {:ok, ^prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    refute_receive {:test_recording_writer_opened, _caller, _source, _stream}

    push(context, context.caller, 1, 0)
    assert_receive {:test_recording_chunk, "full-mix", %{sequence: 0}}

    assert_receive {:test_recording_chunk, caller_stream,
                    %{sequence: 0, source_participant_ids: [caller]}}

    assert caller == context.caller
    assert {:ok, snapshot} = Authority.admit(context.authority, context.joining)
    assert snapshot == context.candidate.snapshot

    for resource <- prepared.resources do
      assert {:ok, ^resource, :ready} = resource.adapter.readiness_binding(resource)
    end

    assert {:error, :stale_preparation} =
             RoomRecording.discard_policy(context.recording, prepared.token)

    push(context, context.caller, 2, 2)
    assert_receive {:test_recording_chunk, "full-mix", %{sequence: 1}}
    assert_receive {:test_recording_chunk, ^caller_stream, %{sequence: 1}}
    push(context, context.joining, 1, 4)
    assert_receive {:test_recording_chunk, "full-mix", %{sequence: 2}}

    assert_receive {:test_recording_chunk, _joining_stream,
                    %{sequence: 0, source_participant_ids: [joining]}}

    assert joining == context.joining
    refute_receive {:test_recording_writer_opened, _caller, _source, _stream}
  end

  for restoration <- [:live_tracks, :new_candidate] do
    @tag restoration: restoration
    test "discard and phase loss close only pending writers and permit #{restoration}", %{
      restoration: restoration
    } do
      context = start_context()
      phase = start_supervised!({Agent, fn -> :phase end})
      options = Keyword.put(context.options, :owner, phase)
      assert {:ok, live, :ready} = RoomRecording.readiness(context.recording)

      assert {:ok, prepared} =
               RoomRecording.prepare_policy(
                 context.recording,
                 context.candidate,
                 tracks(context),
                 options
               )

      assert_receive {:test_recording_writer_opened, source, source, _stream}
      monitor = Process.monitor(source)
      assert :ok = RoomRecording.discard_policy(context.recording, prepared.token)
      assert_receive {:DOWN, ^monitor, :process, ^source, _reason}
      assert {:ok, ^live, :ready} = RoomRecording.readiness(context.recording)

      assert {:ok, retry} =
               RoomRecording.prepare_policy(
                 context.recording,
                 context.candidate,
                 tracks(context),
                 options
               )

      assert_receive {:test_recording_writer_opened, replacement, replacement, _stream}
      refute replacement == source
      monitor = Process.monitor(replacement)
      stop_supervised!(Agent)
      assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000

      assert {:error, :policy_not_ready} =
               Enforcer.apply(context.recording, context.candidate.snapshot, 1_000)

      case restoration do
        :live_tracks ->
          assert :ok =
                   RoomRecording.prepare_tracks(
                     context.recording,
                     [track(context.caller)],
                     Snapshot.interval(context.candidate.base_snapshot, :recording)
                   )

          assert {:error, :policy_not_ready} =
                   Enforcer.apply(context.recording, context.candidate.snapshot, 1_000)

          assert :ok = RoomRecording.discard_policy(context.recording, retry.token)

        :new_candidate ->
          assert {:error, :preparation_conflict} =
                   RoomRecording.prepare_policy(
                     context.recording,
                     context.candidate,
                     tracks(context),
                     options
                   )

          assert {:ok, fresh} =
                   RoomRecording.prepare_policy(
                     context.recording,
                     context.candidate,
                     tracks(context),
                     context.options
                   )

          refute fresh.token == retry.token

          assert {:error, :stale_preparation} =
                   RoomRecording.discard_policy(context.recording, retry.token)

          assert :ok = RoomRecording.discard_policy(context.recording, fresh.token)
      end

      assert {:ok, ^live, :ready} = RoomRecording.readiness(context.recording)
      assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
      push(context, context.caller, 1, 0)
      assert_receive {:test_recording_chunk, "full-mix", %{sequence: 0}}
    end
  end

  test "a local writer must become ready before the future policy can be adopted" do
    readiness = :atomics.new(1, [])
    context = start_context(readiness: readiness)
    :ok = :atomics.put(readiness, 1, 2)

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    recorder = Enum.find(prepared.resources, &(&1.kind == :recording))
    assert {:ok, ^recorder, :preparing} = RoomRecording.readiness_binding(recorder)

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.recording, context.candidate.snapshot, 1_000)

    :ok = :atomics.put(readiness, 1, 0)
    assert {:ok, ^recorder, :ready} = RoomRecording.readiness_binding(recorder)
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.joining)
    assert {:ok, ^recorder, :ready} = RoomRecording.readiness_binding(recorder)
  end

  test "refresh retains pending writers and changed recording permission uses prepared subscriptions" do
    context = start_context()

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    assert_receive {:test_recording_writer_opened, source, source, _stream}
    assert {:ok, base} = Authority.admit(context.authority, context.observer)
    resource = Enum.find(prepared.resources, &(&1.kind == :recording))
    assert {:error, :unavailable} = RoomRecording.readiness_binding(resource)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(base.present_participant_ids, context.joining)
             )

    assert {:ok, refreshed} =
             RoomRecording.prepare_policy(
               context.recording,
               candidate,
               tracks(context),
               context.options
             )

    assert refreshed.token == prepared.token
    refute_receive {:test_recording_writer_opened, _caller, _source, _stream}
    assert {:ok, _} = Authority.admit(context.authority, context.joining)

    assert {:ok, denied} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(candidate.snapshot.present_participant_ids, context.restricted)
             )

    next_options = Keyword.put(context.options, :attempt_id, "deny-recording")

    assert {:ok, prepared_denial} =
             RoomRecording.prepare_policy(context.recording, denied, [], next_options)

    assert Enum.any?(
             prepared_denial.resources,
             &(&1.kind == :recording_subscription and
                 match?({_id, :prepared_policy, _token}, &1.binding))
           )

    assert {:ok, _} = Authority.admit(context.authority, context.restricted)

    for resource <- prepared_denial.resources do
      assert {:ok, ^resource, :ready} = resource.adapter.readiness_binding(resource)
    end

    push(context, context.caller, 1, 0)
    refute_receive {:test_recording_chunk, _stream, _chunk}
  end

  test "an unchanged full-mix writer retains its exact readiness descriptor" do
    context = start_context(full_mix_only: true)
    current = Authority.snapshot(context.authority)

    assert {:ok, candidate} =
             Authority.preview_presence(context.authority, current.present_participant_ids)

    assert {:ok, live, :ready} = RoomRecording.readiness(context.recording)

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(context.recording, candidate, [], context.options)

    assert live in prepared.resources
    assert :ok = RoomRecording.discard_policy(context.recording, prepared.token)
    assert {:ok, ^live, :ready} = RoomRecording.readiness(context.recording)
  end

  test "an adopted descriptor refreshes readiness for a later unaffected policy" do
    readiness = :atomics.new(1, [])
    context = start_context(readiness: readiness)

    assert {:ok, first} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    assert {:ok, base} = Authority.admit(context.authority, context.joining)
    live = Enum.find(first.resources, &(&1.kind == :recording))

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(base.present_participant_ids, context.observer)
             )

    :ok = :atomics.put(readiness, 1, 2)
    options = Keyword.put(context.options, :attempt_id, "unaffected-recording")

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(context.recording, candidate, tracks(context), options)

    assert live in prepared.resources
    assert {:ok, ^live, :preparing} = RoomRecording.readiness_binding(live)
    :ok = :atomics.put(readiness, 1, 0)
    assert {:ok, ^live, :ready} = RoomRecording.readiness_binding(live)
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.observer)
    assert {:ok, ^live, :ready} = RoomRecording.readiness_binding(live)
  end

  test "losing the mixer terminates the recorder even while a policy is prepared" do
    context = start_context()

    assert {:ok, _prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    monitor = Process.monitor(context.recording)
    recording = context.recording
    stop_supervised!({RoomMixer, context.identity.incarnation_id})

    assert_receive {:DOWN, ^monitor, :process, ^recording,
                    {:shutdown, {:room_mixer_unavailable, _reason}}},
                   1_000
  end

  test "losing a required writer after collection invalidates policy adoption" do
    writer = start_supervised!({Agent, fn -> :writer end})
    context = start_context(resource_instance: writer)

    assert {:ok, prepared} =
             RoomRecording.prepare_policy(
               context.recording,
               context.candidate,
               tracks(context),
               context.options
             )

    recording = context.recording
    token = prepared.token
    stop_supervised!(Agent)
    assert_receive {:vxpipe_recording_policy_failed, ^recording, ^token}, 1_000

    assert {:error, :policy_not_ready} =
             Enforcer.apply(recording, context.candidate.snapshot, 1_000)

    assert :ok = RoomRecording.discard_policy(recording, token)
  end

  defp tracks(context), do: Enum.sort([track(context.caller), track(context.joining)])
  defp track(id), do: {:individual_track, id, "connection-#{id}", "track-#{id}"}

  defp push(context, id, sequence, timestamp) do
    policy = Authority.snapshot(context.authority)

    frame =
      struct!(
        NormalizedFrame,
        Map.merge(context.identity, %{
          source_participant_id: id,
          connection_id: "connection-#{id}",
          track_id: "track-#{id}",
          sequence_number: sequence,
          timestamp: timestamp,
          policy_revision: Snapshot.interval(policy, :audio_input, id),
          sample_rate: 8_000,
          channels: 1,
          payload: <<1::little-signed-16, 2::little-signed-16>>
        })
      )

    assert :ok = RoomMixer.push(context.mixer, frame)
    assert {:ok, _counts} = RoomMixer.flush_through(context.mixer, timestamp)
  end

  defp start_context(writer_options \\ []) do
    {full_mix_only?, writer_options} = Keyword.pop(writer_options, :full_mix_only, false)
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "recording-preparation-#{suffix}"

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "transfer"}
    }

    participants = Map.new(["caller", "joining", "observer", "restricted"], &{&1, human})

    participants =
      participants
      |> put_in(["observer", :while_present], %{save_transcripts: false})
      |> put_in(["restricted", :while_present], %{record_audio: false})

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "joining",
                 defaults: %{capabilities: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "recording-preparation",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "recording-preparation", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-recording",
               actor_id: "actor-recording",
               call_id: "call-#{suffix}",
               room_id: "room-#{suffix}"
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{},
               host_tools: %{}
             })

    authority =
      start_supervised!(
        Supervisor.child_spec({Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    identities =
      Map.new([:caller, :joining, :observer, :restricted], fn key ->
        {key, Map.fetch!(plan.participants, Atom.to_string(key)).participant_id}
      end)

    assert {:ok, base} = Authority.admit(authority, identities.caller)
    identity = %{tenant_id: plan.tenant_id, room_id: plan.room_id, incarnation_id: incarnation}
    recording_token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             recording_token: recording_token,
             sample_rate: 8_000,
             channels: 1,
             frame_samples: 2,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4
           ]}
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, mixer)

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(identity) ++
           [
             call_id: plan.call_id,
             mixer: mixer,
             recording_token: recording_token,
             targets:
               if(full_mix_only?,
                 do: [:full_mix],
                 else: [:full_mix, {:individual_tracks, [identities.caller, identities.joining]}]
               ),
             writer: {TestRecordingWriter, Keyword.put(writer_options, :observer, self())},
             maximum_pull_frames: 4
           ]}
      )

    unless full_mix_only? do
      assert :ok =
               RoomRecording.prepare_tracks(
                 recording,
                 [track(identities.caller)],
                 Snapshot.interval(base, :recording)
               )
    end

    assert_receive {:test_recording_writer_opened, _caller, ^recording, %{mode: :full_mix}}

    unless full_mix_only? do
      assert_receive {:test_recording_writer_opened, _caller, ^recording,
                      %{mode: {:individual_track, _, _, _}}}
    end

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, identities.joining)
             )

    Map.merge(identities, %{
      authority: authority,
      mixer: mixer,
      recording: recording,
      identity: identity,
      candidate: candidate,
      options: [
        owner: self(),
        attempt_id: "recording-policy",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    })
  end
end
