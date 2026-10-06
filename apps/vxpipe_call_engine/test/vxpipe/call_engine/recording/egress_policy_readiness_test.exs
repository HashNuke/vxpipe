defmodule Vxpipe.CallEngine.Recording.EgressPolicyReadinessTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    RoomMixer,
    RoomRecording,
    TestRecordingWriter,
    TestRecordingOutput
  }

  alias Vxpipe.CallEngine.Media.EgressAcceptedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.Readiness.{Collector, RecordingPreparation}
  alias Vxpipe.CallEngine.Recording.{EgressHandoff, EgressReadiness}

  test "prepares the existing tap while recording is denied and adopts without replacing it" do
    context = start_context()
    %{native_resource: native, candidate: candidate, mixer: mixer, identity: identity} = context

    assert {:error, :unavailable} =
             EgressReadiness.prepare(native, identity, mixer, candidate.snapshot)

    assert {:ok, prepared} = RoomMixer.prepare_policy(mixer, candidate, context.options)
    [policy_resource] = prepared.resources

    assert {:ok, binding} =
             EgressReadiness.prepare_candidate(
               native,
               identity,
               mixer,
               candidate,
               policy_resource
             )

    assert binding.resources == [binding.resource, policy_resource]
    assert binding.resource.generation == native.generation
    assert {:ok, observed, :ready} = EgressReadiness.readiness_binding(binding.resource)
    assert observed == binding.resource
    assert Authority.snapshot(context.authority) == candidate.base_snapshot
    assert :ignored = EgressHandoff.offer(context.handoff, frame(context))
    assert {:error, :unavailable} = RoomMixer.recording_egress_readiness(mixer, context.handoff)

    assert {:ok, snapshot} = Authority.leave(context.authority, context.restricted)
    assert snapshot == candidate.snapshot

    for resource <- binding.resources do
      assert {:ok, ^resource, :ready} = resource.adapter.readiness_binding(resource)
    end

    assert {:ok, ^native, :ready} = TestRecordingOutput.readiness(context.native)
    assert {:ok, installed} = EgressReadiness.prepare(native, identity, mixer, snapshot)
    assert installed.resource == binding.resource
    assert :ok = EgressHandoff.offer(context.handoff, frame(context))
  end

  test "candidate recording selection includes the prepared tap and its mixer gate" do
    context = start_context()

    recording =
      start_supervised!(
        {RoomRecording,
         Map.to_list(Map.take(context.identity, [:tenant_id, :room_id, :incarnation_id])) ++
           [
             call_id: context.plan.call_id,
             mixer: context.mixer,
             recording_token: context.recording_token,
             targets: [{:individual_tracks, [context.receiver]}],
             maximum_pull_frames: 4,
             writer: {TestRecordingWriter, observer: self()}
           ]}
      )

    captured = %{
      candidate: context.candidate,
      room: %{recording: recording, room_mixer: context.mixer},
      inventory: %{
        recording_participant_ids: MapSet.new([context.receiver]),
        recording_targets: [{:individual_tracks, [context.receiver]}]
      },
      binding: %{
        plan: %{participants: %{"receiver" => %{kind: :agent, participant_id: context.receiver}}}
      }
    }

    connections = %{
      context.identity.connection_id => %{
        identity: context.identity,
        input_track: nil,
        resources: [context.native_resource]
      }
    }

    assert {:ok, prepared_mixer} =
             RoomMixer.prepare_policy(context.mixer, context.candidate, context.options)

    mixer_resource = Enum.find(prepared_mixer.resources, &(&1.kind == :room_mixer))

    assert {:ok, tracks, resources, [handle]} =
             RecordingPreparation.prepare_candidate(
               captured,
               connections,
               context.options,
               mixer_resource
             )

    assert tracks == [
             {:individual_track, context.receiver, context.identity.connection_id, "agent-egress"}
           ]

    assert mixer_resource in resources
    assert Enum.count(resources, &(&1.kind == :recording_output)) == 1
    assert Enum.count(resources, &(&1.kind == :recording_writer)) == 1
    assert_receive {:test_recording_writer_opened, source, source, _stream}
    refute source == recording

    for resource <- resources do
      assert {:ok, ^resource, :ready} = resource.adapter.readiness_binding(resource)
    end

    assert :ignored = EgressHandoff.offer(context.handoff, frame(context))
    assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
    monitor = Process.monitor(source)
    assert :ok = RoomRecording.discard_policy(recording, handle.token)
    assert_receive {:DOWN, ^monitor, :process, ^source, _reason}
    assert :ok = RoomMixer.discard_policy(context.mixer, prepared_mixer.token)
    assert {:ok, native, :ready} = TestRecordingOutput.readiness(context.native)
    assert native == context.native_resource
  end

  test "discarded policy evidence closes collection while the unchanged physical tap stays ready" do
    context = start_context()

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(context.mixer, context.candidate, context.options)

    [policy_resource] = prepared.resources

    assert {:ok, binding} =
             EgressReadiness.prepare_candidate(
               context.native_resource,
               context.identity,
               context.mixer,
               context.candidate,
               policy_resource
             )

    collector =
      start_supervised!(
        {Collector,
         Keyword.merge(context.options,
           incarnation_id: context.identity.incarnation_id,
           resources: binding.resources
         )}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert :ok = RoomMixer.discard_policy(context.mixer, prepared.token)
    :ok = Collector.refresh(collector)
    assert %{status: :preparing} = Collector.snapshot(collector)
    assert {:error, :unavailable} = RoomMixer.readiness_binding(policy_resource)
    assert {:ok, tap, :ready} = EgressReadiness.readiness_binding(binding.resource)
    assert tap == binding.resource
    assert :ignored = EgressHandoff.offer(context.handoff, frame(context))

    assert {:error, :unavailable} =
             EgressReadiness.prepare_candidate(
               context.native_resource,
               context.identity,
               context.mixer,
               context.candidate,
               policy_resource
             )
  end

  test "rejects installed or relabeled policy evidence and a stale candidate" do
    context = start_context()
    assert {:ok, installed, :ready} = RoomMixer.readiness(context.mixer)

    assert {:ok, prepared} =
             RoomMixer.prepare_policy(context.mixer, context.candidate, context.options)

    [policy_resource] = prepared.resources

    for resource <- [
          installed,
          %{installed | policy_interval: policy_resource.policy_interval},
          %{policy_resource | instance: self()}
        ] do
      assert {:error, :unavailable} =
               EgressReadiness.prepare_candidate(
                 context.native_resource,
                 context.identity,
                 context.mixer,
                 context.candidate,
                 resource
               )
    end

    assert {:ok, _} = Authority.leave(context.authority, context.restricted)

    assert {:error, :unavailable} =
             EgressReadiness.prepare_candidate(
               context.native_resource,
               context.identity,
               context.mixer,
               context.candidate,
               policy_resource
             )
  end

  defp frame(context) do
    struct!(
      EgressAcceptedFrame,
      Map.merge(context.identity, %{
        source_participant_id: context.receiver,
        sample_rate: 48_000,
        channels: 1,
        payload: :binary.copy(<<1::little-signed-16>>, 960)
      })
      |> Map.delete(:participant_id)
    )
  end

  defp start_context do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "recording-tap-policy-#{suffix}"

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"}
    }

    participants = Map.new(["caller", "receiver", "restricted"], &{&1, human})
    participants = put_in(participants, ["restricted", :while_present], %{record_audio: false})

    assert {:ok, call_spec} =
             CallSpec.new(
               %{
                 schema_version: "20260915.01",
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 participants: participants
               },
               resource_id: "recording-tap-policy",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "recording-tap-policy", revision: 1},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-recording",
               actor_id: "actor-recording"
             )

    assert {:ok, plan} =
             CallSpecCompiler.compile(call_spec, invocation, %{
               host_tools: %{}
             })

    authority =
      start_supervised!(
        Supervisor.child_spec({Authority, plan: plan, incarnation_id: incarnation},
          significant: false
        )
      )

    caller = Map.fetch!(plan.participants, "caller").participant_id
    receiver = Map.fetch!(plan.participants, "receiver").participant_id
    restricted = Map.fetch!(plan.participants, "restricted").participant_id
    assert {:ok, _} = Authority.admit(authority, caller)
    assert {:ok, _} = Authority.admit(authority, receiver)
    assert {:ok, base} = Authority.admit(authority, restricted)

    room_identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: incarnation
    }

    recording_token = make_ref()

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(room_identity) ++
           [
             recording_token: recording_token,
             sample_rate: 48_000,
             channels: 1,
             frame_samples: 960,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4
           ]}
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, mixer)

    identity =
      Map.merge(room_identity, %{participant_id: caller, connection_id: "listener-connection"})

    native = start_supervised!({TestRecordingOutput, observer: self(), participant_id: caller})
    assert {:ok, native_resource, :ready} = TestRecordingOutput.readiness(native)
    assert {:ok, handoff} = RoomMixer.open_recording_egress(mixer, identity.connection_id)
    :ok = TestRecordingOutput.bind(native, handoff)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.delete(base.present_participant_ids, restricted)
             )

    %{
      plan: plan,
      recording_token: recording_token,
      authority: authority,
      candidate: candidate,
      mixer: mixer,
      identity: identity,
      native: native,
      native_resource: native_resource,
      handoff: handoff,
      restricted: restricted,
      receiver: receiver,
      options: [
        owner: self(),
        attempt_id: "recording-tap-policy",
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    }
  end
end
