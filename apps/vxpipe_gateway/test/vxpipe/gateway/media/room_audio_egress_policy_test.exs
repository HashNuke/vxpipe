defmodule Vxpipe.Gateway.Media.RoomAudioEgressPolicyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    ConnectionAttachment,
    DefinitionCompiler,
    RoomAudioHandle,
    RoomMixer
  }

  alias Vxpipe.CallEngine.Media.{NormalizedFrame, OutputSink}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer, Snapshot}
  alias Vxpipe.Gateway.Media.{OutputArbiter, RoomAudioEgress, SharedOutputPipeline}
  alias Vxpipe.Gateway.WebRTC.{AudioEgress, ConnectionPeerSupervisor}

  test "adopts an affected output policy without replacing its live subscription or pipeline" do
    context = start_context(:receiver)
    assert :ok = RoomAudioEgress.hold(context.egress, 1)
    assert {:ok, before} = RoomAudioEgress.readiness_resources(context.egress)
    assert {:ok, codec, :ready} = AudioEgress.readiness(context.native)
    assert {:ok, prepared} = prepare(context)
    assert prepared.change == :retain
    assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
    assert {:ok, ^before} = RoomAudioEgress.readiness_resources(context.egress)
    [resource, subscription, route] = prepared.resources
    assert resource.generation == hd(before).generation
    assert route == List.last(before)
    assert {:ok, ^resource, :ready} = RoomAudioEgress.readiness_binding(resource)
    assert {:ok, committed} = Authority.admit(context.authority, context.destination)
    assert committed == context.candidate.snapshot
    assert {:ok, ^resource, :ready} = RoomAudioEgress.readiness_binding(resource)

    assert {:ok, [^resource, ^subscription, ^route]} =
             RoomAudioEgress.readiness_resources(context.egress)

    assert :ok = RoomAudioEgress.release(context.egress, 1)
    push(context, 1, 0)
    assert_receive {:rtp, %{sequence_number: 0, timestamp: 0}}
    assert {:ok, ^codec, :ready} = AudioEgress.readiness(context.native)
  end

  test "prepares a joining output behind closed gates and releases its adopted subscription" do
    context = start_context(:destination)
    assert :ok = OutputSink.hold(context.output, 1)
    assert {:ok, prepared} = prepare(context)
    assert prepared.change == :start
    [resource, subscription, route] = prepared.resources
    assert {:ok, ^resource, :ready} = RoomAudioEgress.readiness_binding(resource)
    assert {:error, :preparation_pending} = OutputSink.release(context.output, 1)
    push(context, 1, 0)
    refute_receive {:rtp, _}
    ready_request = :gen_server.send_request(context.egress, :await_ready)
    _ = :sys.get_state(context.egress)
    assert :timeout = :gen_server.wait_response(ready_request, 0)
    assert {:ok, _committed} = Authority.admit(context.authority, context.destination)
    assert {:reply, :ok} = :gen_server.wait_response(ready_request, 1_000)

    assert {:ok, [^resource, ^subscription, ^route]} =
             RoomAudioEgress.readiness_resources(context.egress)

    push(context, 2, 960)
    refute_receive {:rtp, _}
    assert :ok = RoomAudioEgress.release(context.egress, 1)
    push(context, 3, 1920)
    assert_receive {:rtp, %{sequence_number: 0, timestamp: 0}}

    assert {:error, :stale_preparation} =
             RoomAudioEgress.discard_policy(context.egress, prepared.token)
  end

  test "unchanged preparation and adoption preserve all existing output descriptors" do
    context = start_context(:receiver, %{record_audio: false})
    assert :ok = RoomAudioEgress.hold(context.egress, 1)
    assert {:ok, before} = RoomAudioEgress.readiness_resources(context.egress)
    assert {:ok, prepared} = prepare(context)
    assert prepared.resources == before
    assert {:ok, repeated} = prepare(context)
    assert repeated == prepared
    assert {:ok, _} = Authority.admit(context.authority, context.destination)
    assert {:ok, ^before} = RoomAudioEgress.readiness_resources(context.egress)
    assert :ok = RoomAudioEgress.release(context.egress, 1)
  end

  test "discard cancels a joining route and cannot cancel its successor" do
    context = start_context(:destination)
    assert :ok = OutputSink.hold(context.output, 1)
    assert {:ok, codec, :ready} = AudioEgress.readiness(context.native)
    assert {:ok, first} = prepare(context)
    assert :ok = RoomAudioEgress.discard_policy(context.egress, first.token)
    assert {:error, :unavailable} = RoomAudioEgress.readiness_binding(hd(first.resources))
    assert {:ok, second} = prepare(context)
    refute second.token == first.token

    assert {:error, :stale_preparation} =
             RoomAudioEgress.discard_policy(context.egress, first.token)

    assert {:ok, resource, :ready} = RoomAudioEgress.readiness_binding(hd(second.resources))
    assert resource == hd(second.resources)
    assert :ok = RoomAudioEgress.discard_policy(context.egress, second.token)
    assert :ok = OutputSink.release(context.output, 1)
    assert {:ok, ^codec, :ready} = AudioEgress.readiness(context.native)
  end

  test "losing the phase owner fails prepared evidence while preserving the source output" do
    context = start_context(:receiver)
    owner = start_supervised!({Agent, fn -> :phase end}, id: :phase)
    context = %{context | options: Keyword.put(context.options, :owner, owner)}
    assert :ok = RoomAudioEgress.hold(context.egress, 1)
    assert {:ok, before} = RoomAudioEgress.readiness_resources(context.egress)
    assert {:ok, prepared} = prepare(context)
    stop_supervised!(:phase)
    _ = :sys.get_state(context.egress)
    assert {:ok, resource, :failed} = RoomAudioEgress.readiness_binding(hd(prepared.resources))
    assert resource == hd(prepared.resources)
    assert {:ok, ^before} = RoomAudioEgress.readiness_resources(context.egress)
    assert :ok = RoomAudioEgress.discard_policy(context.egress, prepared.token)
    assert :ok = RoomAudioEgress.release(context.egress, 1)
    push(context, 1, 0)
    assert_receive {:rtp, _}
  end

  test "rejecting a foreign subscription does not hold that other room's output" do
    context = start_context(:receiver)
    foreign = start_context(:receiver)
    assert :ok = RoomAudioEgress.hold(context.egress, 1)
    assert {:ok, mixer} = prepare_mixer(foreign)
    handle = Map.fetch!(mixer.subscriptions, foreign.connection <> ":room-output")

    assert {:error, :stale_candidate} =
             RoomAudioEgress.prepare_policy(
               context.egress,
               context.candidate,
               handle,
               context.options
             )

    push(foreign, 1, 0)
    assert_receive {:rtp, _}
  end

  test "a replaced native room binding cannot adopt previously collected output readiness" do
    context = start_context(:receiver)
    assert :ok = RoomAudioEgress.hold(context.egress, 1)
    assert {:ok, _prepared} = prepare(context)
    identity = Map.put(context.identity, :participant_id, context.participant)
    assert {:ok, _replacement} = OutputArbiter.bind_room(context.output, identity)

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.egress, context.candidate.snapshot, 1_000)
  end

  test "a private joining route survives unrelated membership and candidate refresh" do
    context = start_context(:destination)
    assert :ok = OutputSink.hold(context.output, 1)
    assert {:ok, prepared} = prepare(context)
    assert {:ok, base} = Authority.admit(context.authority, context.observer)
    assert {:error, :unavailable} = RoomAudioEgress.readiness_binding(hd(prepared.resources))

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(base.present_participant_ids, context.destination)
             )

    context = %{context | candidate: candidate}
    assert {:ok, refreshed} = prepare(context)
    assert refreshed.token == prepared.token

    for {before, current} <- Enum.zip(prepared.resources, refreshed.resources) do
      assert current.generation == before.generation
      assert current.configuration == before.configuration
      assert current.binding == before.binding
    end

    assert {:ok, ^refreshed} = prepare(context)
    assert {:ok, _} = Authority.admit(context.authority, context.destination)
    assert :ok = RoomAudioEgress.release(context.egress, 1)
    push(context, 1, 0)
    assert_receive {:rtp, _}
  end

  test "prepared output requires a queue that actually notifies its egress consumer" do
    context = start_context(:destination)
    assert :ok = OutputSink.hold(context.output, 1)
    assert {:ok, mixer} = prepare_mixer(context, self())
    handle = Map.fetch!(mixer.subscriptions, context.connection <> ":room-output")

    assert {:error, :invalid_subscription_owner} =
             RoomAudioEgress.prepare_policy(
               context.egress,
               context.candidate,
               handle,
               context.options
             )
  end

  defp prepare(context) do
    with {:ok, mixer} <- prepare_mixer(context) do
      handle = Map.fetch!(mixer.subscriptions, context.connection <> ":room-output")
      RoomAudioEgress.prepare_policy(context.egress, context.candidate, handle, context.options)
    end
  end

  defp prepare_mixer(context, subscriber \\ nil) do
    subscription =
      Map.to_list(context.identity) ++
        [
          id: context.connection <> ":room-output",
          recipient_participant_id: context.participant,
          subscriber: subscriber || context.egress,
          mode: :mix_minus
        ]

    RoomMixer.prepare_policy(
      context.mixer,
      context.candidate,
      Keyword.put(context.options, :subscriptions, [subscription])
    )
  end

  defp start_context(
         selected,
         restriction \\ %{audio_routes: %{"caller" => ["receiver", "destination"]}}
       ) do
    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "egress-policy-" <> suffix
    connection = "output-" <> suffix

    human = %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "transfer"},
      capabilities: %{}
    }

    participants = Map.new(["caller", "receiver", "destination", "observer"], &{&1, human})

    participants =
      put_in(participants["destination"][:while_present], restriction)

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 defaults: %{capabilities: %{}},
                 call_variables: %{sections: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "output-policy",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "output-policy", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-output-policy",
               actor_id: "actor-output-policy",
               call_id: "call-" <> suffix,
               room_id: "room-" <> suffix
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
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
    destination = Map.fetch!(plan.participants, "destination").participant_id
    observer_participant = Map.fetch!(plan.participants, "observer").participant_id
    participant = if selected == :receiver, do: receiver, else: destination
    assert {:ok, _} = Authority.admit(authority, caller)
    assert {:ok, base} = Authority.admit(authority, receiver)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, destination)
             )

    identity = %{tenant_id: plan.tenant_id, room_id: plan.room_id, incarnation_id: incarnation}

    mixer =
      start_supervised!(
        {RoomMixer,
         Map.to_list(identity) ++
           [
             sample_rate: 48_000,
             channels: 1,
             frame_samples: 960,
             maximum_buffered_timestamps: 4,
             maximum_sink_frames: 4
           ]}
      )

    assert {:ok, ^base} = Authority.register_enforcer(authority, mixer)
    start_supervised!({ConnectionPeerSupervisor, connection_id: connection})
    observer = self()

    media_identity =
      Map.to_list(identity) ++ [participant_id: participant, connection_id: connection]

    native =
      start_supervised!(
        {AudioEgress,
         media_identity ++
           [
             peer_connection: self(),
             track_id: "track",
             encoder: {Vxpipe.Gateway.TestOpusEncoder, [observer: self()]},
             send_rtp: fn _, _, packet ->
               send(observer, {:rtp, packet})
               :ok
             end
           ]}
      )

    output =
      start_supervised!(
        {OutputArbiter,
         media_identity ++ [native_output: native, native_adapter: AudioEgress, owner: self()]}
      )

    attachment = %ConnectionAttachment{
      room_monitor: Process.monitor(mixer),
      media_ingress: nil,
      room_audio_output_mode: :mix_minus,
      room_audio: %RoomAudioHandle{
        mixer: mixer,
        media_policy_authority: authority,
        configuration: %{}
      }
    }

    egress =
      start_supervised!(
        {RoomAudioEgress,
         media_identity ++
           [
             attachment: attachment,
             owner: self(),
             pipeline: SharedOutputPipeline,
             pipeline_options: [output_sink: output]
           ]}
      )

    if selected == :receiver do
      assert :ok = RoomAudioEgress.activate(egress)
      assert :ok = RoomAudioEgress.await_ready(egress)
    end

    assert {:ok, ^base} = Authority.register_enforcer(authority, egress)

    %{
      egress: egress,
      mixer: mixer,
      authority: authority,
      candidate: candidate,
      identity: identity,
      connection: connection,
      participant: participant,
      destination: destination,
      observer: observer_participant,
      caller: caller,
      native: native,
      output: output,
      options: [
        owner: self(),
        attempt_id: connection,
        generation: 1,
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    }
  end

  defp push(context, sequence, timestamp) do
    snapshot = Authority.snapshot(context.authority)

    frame =
      struct!(
        NormalizedFrame,
        Map.merge(context.identity, %{
          source_participant_id: context.caller,
          connection_id: "source",
          track_id: "source-track",
          sequence_number: sequence,
          timestamp: timestamp,
          policy_revision: Snapshot.interval(snapshot, :audio_input, context.caller),
          sample_rate: 48_000,
          channels: 1,
          payload: :binary.copy(<<1, 0>>, 960)
        })
      )

    assert :ok = RoomMixer.push(context.mixer, frame)
    assert {:ok, _} = RoomMixer.flush_through(context.mixer, timestamp)
  end
end
