defmodule Vxpipe.Gateway.Media.RoomAudioIngressPolicyTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler}
  alias Vxpipe.CallEngine.Media.{AudioFrame, NormalizedFrame}
  alias Vxpipe.CallEngine.MediaPolicy.{Authority, Enforcer}
  alias Vxpipe.CallEngine.Readiness.Collector
  alias Vxpipe.Gateway.Media.{PCMFrame, RoomAudioIngress}
  alias Vxpipe.Gateway.TestPreparedAudioPipeline, as: Pipeline
  alias Vxpipe.Gateway.WebRTC.ConnectionPeerSupervisor

  @track %{track_id: "track-input", codec: :opus, sample_rate: 48_000, channels: 2}

  test "prepares the replacement decoder before committing its policy" do
    context = start_context()
    %{ingress: ingress, pipeline: original, pipeline_id: original_id} = context
    assert {:ok, live_resource, :ready} = RoomAudioIngress.readiness(ingress)

    assert {:ok, prepared} =
             RoomAudioIngress.prepare_policy(ingress, context.candidate, @track, context.options)

    assert prepared.change == :replace
    assert_receive {:prepared_pipeline_started, replacement, replacement_id}
    assert {:ok, ^live_resource, :ready} = RoomAudioIngress.readiness(ingress)
    assert {:error, :policy_not_ready} = Enforcer.apply(ingress, context.candidate.snapshot, 500)
    assert :ok = RoomAudioIngress.push(ingress, audio_frame(context, 1))
    assert_receive {:prepared_pipeline_push, ^original, %AudioFrame{sequence_number: 1}}
    send(ingress, {:vxpipe_audio_pipeline, original_id, pcm_frame(context, 0)})
    assert_receive {:test_room_audio, %NormalizedFrame{sequence_number: 1}}

    send(ingress, {:vxpipe_audio_pipeline, replacement_id, pcm_frame(context, 0)})
    refute_receive {:test_room_audio, %NormalizedFrame{}}
    collector = collect(prepared.resources, context)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing}}, 1_000
    assert :ok = Pipeline.ready(replacement)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    [resource, decoder] = prepared.resources
    assert decoder.instance == replacement
    assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    monitor = Process.monitor(original)
    Agent.update(context.clock, fn _now -> 1_030 end)
    assert {:ok, committed} = Authority.admit(context.authority, context.destination)
    assert committed == context.candidate.snapshot
    assert_receive {:DOWN, ^monitor, :process, ^original, _reason}
    assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    refute_receive {:prepared_pipeline_started, _, _}

    assert {:error, :stale_policy_interval} =
             RoomAudioIngress.push(ingress, audio_frame(context, 2))

    assert :ok = RoomAudioIngress.push(ingress, %{audio_frame(context, 3) | received_at: 1_040})
    assert_receive {:prepared_pipeline_push, ^replacement, %AudioFrame{sequence_number: 3}}
    send(ingress, {:vxpipe_audio_pipeline, original_id, pcm_frame(context, 0)})
    refute_receive {:test_room_audio, %NormalizedFrame{}}
    send(ingress, {:vxpipe_audio_pipeline, replacement_id, pcm_frame(context, 960)})

    assert_receive {:test_room_audio,
                    %NormalizedFrame{
                      sequence_number: 2,
                      timestamp: 960,
                      policy_revision: interval
                    }}

    assert interval == resource.policy_interval
    assert {:error, :stale_preparation} = RoomAudioIngress.discard_policy(ingress, prepared.token)
  end

  test "discarding a preparation leaves the installed decoder and policy available" do
    context = start_context()
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)

    assert {:ok, prepared} =
             RoomAudioIngress.prepare_policy(
               context.ingress,
               context.candidate,
               @track,
               context.options
             )

    assert_receive {:prepared_pipeline_started, replacement, _id}
    monitor = Process.monitor(replacement)
    assert :ok = RoomAudioIngress.discard_policy(context.ingress, prepared.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
    assert {:error, :unavailable} = RoomAudioIngress.readiness_binding(hd(prepared.resources))
  end

  test "retains both decoders when an unrelated membership revision changes the candidate" do
    context = start_context()
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:ok, prepared} = prepare(context)
    assert_receive {:prepared_pipeline_started, replacement, _id}
    assert {:ok, ^prepared} = prepare(context)
    extended = Keyword.update!(context.options, :deadline_ms, &(&1 + 1_000))
    assert {:error, :preparation_conflict} = prepare(%{context | options: extended})
    assert :ok = Pipeline.ready(replacement)
    [resource, decoder] = prepared.resources
    assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    assert {:ok, current} = Authority.admit(context.authority, context.observer)
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:error, :unavailable} = RoomAudioIngress.readiness_binding(resource)

    assert {:ok, candidate} =
             Authority.preview_presence(
               context.authority,
               MapSet.put(current.present_participant_ids, context.destination)
             )

    assert {:ok, refreshed} = prepare(%{context | candidate: candidate})
    assert refreshed.token == prepared.token
    [next_resource, ^decoder] = refreshed.resources
    assert next_resource.generation == resource.generation
    assert next_resource.configuration == resource.configuration
    assert next_resource.policy_interval != resource.policy_interval
    assert {:ok, ^next_resource, :ready} = RoomAudioIngress.readiness_binding(next_resource)
    refute_receive {:prepared_pipeline_started, _, _}
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.destination)
    assert {:ok, ^next_resource, :ready} = RoomAudioIngress.readiness_binding(next_resource)
  end

  test "unaffected policies keep the ordinary decoder resource" do
    context = start_context(restriction: %{save_transcripts: false})
    assert {:ok, original} = RoomAudioIngress.readiness_resources(context.ingress)
    assert {:ok, %{change: :retain, resources: ^original}} = prepare(context)
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.destination)
    assert {:ok, ^original} = RoomAudioIngress.readiness_resources(context.ingress)
    refute_receive {:prepared_pipeline_started, _, _}
  end

  test "membership demand removes and prepares a decoder without changing its permission interval" do
    context = start_context(media_policy: %{record_audio: false})
    base = Authority.snapshot(context.authority)

    assert {:ok, alone} =
             Authority.preview_presence(
               context.authority,
               MapSet.delete(base.present_participant_ids, context.receiver)
             )

    assert {:ok, %{change: :disable, resources: []}} = prepare(%{context | candidate: alone})
    monitor = Process.monitor(context.pipeline)
    assert {:ok, _snapshot} = Authority.leave(context.authority, context.receiver)
    assert_receive {:DOWN, ^monitor, :process, _pipeline, _reason}
    assert :ok = RoomAudioIngress.push(context.ingress, audio_frame(context, 1))

    assert {:ok, joined} =
             Authority.preview_presence(context.authority, base.present_participant_ids)

    assert {:ok, %{change: :replace} = prepared} = prepare(%{context | candidate: joined})
    assert_receive {:prepared_pipeline_started, replacement, _id}
    assert :ok = Pipeline.ready(replacement)
    [resource, _decoder] = prepared.resources
    assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.receiver)
    assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    refute_receive {:prepared_pipeline_started, _, _}
  end

  test "a future denial closes the decoder only when the policy commits" do
    context = start_context(restriction: %{audio_routes: %{}, record_audio: false})
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:ok, %{change: :disable, resources: []}} = prepare(context)
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)
    refute_receive {:prepared_pipeline_started, _, _}
    monitor = Process.monitor(context.pipeline)
    assert {:ok, _snapshot} = Authority.admit(context.authority, context.destination)
    assert_receive {:DOWN, ^monitor, :process, _pipeline, _reason}

    assert :ok = RoomAudioIngress.push(context.ingress, audio_frame(context, 1))

    attachment = %Vxpipe.CallEngine.ConnectionAttachment{
      room_monitor: make_ref(),
      media_ingress: nil,
      room_audio_input_mode: :enabled
    }

    assert :ok =
             Vxpipe.Gateway.Telephony.IncomingAudio.deliver(
               Vxpipe.Gateway.TestRoomAudioEngine,
               attachment,
               context.ingress,
               audio_frame(context, 2)
             )

    refute_receive {:prepared_pipeline_started, _, _}
  end

  test "owner loss cancels only the pending decoder" do
    context = start_context()
    owner = start_supervised!({Agent, fn -> :owner end}, id: :preparation_owner)
    context = %{context | options: Keyword.put(context.options, :owner, owner)}
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:ok, prepared} = prepare(context)
    assert_receive {:prepared_pipeline_started, replacement, _id}
    monitor = Process.monitor(replacement)
    stop_supervised!(:preparation_owner)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:error, :unavailable} = RoomAudioIngress.readiness_binding(hd(prepared.resources))

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.ingress, context.candidate.snapshot, 500)
  end

  test "expiry and stale cleanup cannot remove a later preparation" do
    context = start_context()

    options =
      Keyword.put(context.options, :deadline_ms, System.monotonic_time(:millisecond) + 1_000)

    assert {:ok, prepared} = prepare(%{context | options: options})
    assert_receive {:prepared_pipeline_started, replacement, _id}
    monitor = Process.monitor(replacement)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_500

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.ingress, context.candidate.snapshot, 500)

    assert :ok = RoomAudioIngress.discard_policy(context.ingress, prepared.token)
    assert {:ok, next} = prepare(context)
    assert_receive {:prepared_pipeline_started, next_pipeline, _id}
    assert next.token != prepared.token

    assert {:error, :stale_preparation} =
             RoomAudioIngress.discard_policy(context.ingress, prepared.token)

    send(context.ingress, {:input_policy_expired, prepared.token})
    assert :ok = Pipeline.ready(next_pipeline)
    assert {:ok, _resource, :ready} = RoomAudioIngress.readiness_binding(hd(next.resources))
  end

  test "a failed prepared decoder leaves the current source operational" do
    context = start_context()
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:ok, prepared} = prepare(context)
    assert_receive {:prepared_pipeline_started, replacement, _id}
    monitor = Process.monitor(replacement)
    Process.exit(replacement, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, :killed}
    assert {:error, :unavailable} = RoomAudioIngress.readiness_binding(hd(prepared.resources))
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)

    assert {:error, :policy_not_ready} =
             Enforcer.apply(context.ingress, context.candidate.snapshot, 500)
  end

  test "replacement initialization failure leaves the current decoder installed" do
    context = start_context(pipeline_options: [fail_generation: 2])
    assert {:ok, live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert {:error, :test_pipeline_unavailable} = prepare(context)
    assert {:ok, ^live, :ready} = RoomAudioIngress.readiness(context.ingress)
    assert Authority.snapshot(context.authority) == context.candidate.base_snapshot
  end

  for {transport, pipeline, codec, rate, channels} <- [
        {:webrtc, Vxpipe.Gateway.WebRTC.AudioPipeline, :opus, 48_000, 2},
        {:telnyx, Vxpipe.Gateway.Telephony.Telnyx.AudioIngressPipeline, :opus, 16_000, 1},
        {:twilio, Vxpipe.Gateway.Telephony.Twilio.AudioIngressPipeline, :pcmu, 8_000, 1}
      ] do
    @pipeline pipeline
    @input %{track_id: "prepared-track", codec: codec, sample_rate: rate, channels: channels}

    test "adopts the actual prepared #{transport} decoder" do
      context = start_context(pipeline: @pipeline, track: @input)

      assert {:ok, prepared} =
               RoomAudioIngress.prepare_policy(
                 context.ingress,
                 context.candidate,
                 @input,
                 context.options
               )

      collector = collect(prepared.resources, context)
      assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
      [resource, decoder] = prepared.resources
      assert decoder.adapter == @pipeline
      monitor = Process.monitor(context.pipeline)
      assert {:ok, _snapshot} = Authority.admit(context.authority, context.destination)
      assert_receive {:DOWN, ^monitor, :process, _pipeline, _reason}, 1_000
      assert {:ok, ^resource, :ready} = RoomAudioIngress.readiness_binding(resource)
    end
  end

  defp prepare(context),
    do:
      RoomAudioIngress.prepare_policy(context.ingress, context.candidate, @track, context.options)

  defp start_context(options \\ []) do
    identity = Integer.to_string(System.unique_integer([:positive, :monotonic]))
    incarnation = "prepared-policy-#{identity}"
    connection = "prepared-input-#{identity}"
    participants = Map.new(["caller", "receiver", "destination", "observer"], &{&1, human()})

    participants =
      put_in(
        participants["destination"][:while_present],
        Keyword.get(options, :restriction, %{record_audio: false})
      )

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "receiver",
                 defaults: %{capabilities: %{}},
                 media_policy: Keyword.get(options, :media_policy, %{}),
                 call_variables: %{sections: %{}},
                 participants: participants,
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "input-policy",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "input-policy", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-input-policy",
               actor_id: "actor-input-policy",
               call_id: "call-#{identity}",
               room_id: "room-#{identity}"
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
    observer = Map.fetch!(plan.participants, "observer").participant_id
    assert {:ok, _snapshot} = Authority.admit(authority, caller)
    assert {:ok, base} = Authority.admit(authority, receiver)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, destination)
             )

    start_supervised!({ConnectionPeerSupervisor, connection_id: connection})
    clock = start_supervised!({Agent, fn -> 1_000 end})

    ingress =
      start_supervised!(
        {RoomAudioIngress,
         connection_id: connection,
         attachment: %{observer: self()},
         configuration: %{clock_origin_ms: 0},
         tenant_id: plan.tenant_id,
         room_id: plan.room_id,
         incarnation_id: incarnation,
         participant_id: caller,
         owner: self(),
         engine: Vxpipe.Gateway.TestRoomAudioEngine,
         clock: fn -> Agent.get(clock, & &1) end,
         pipeline: Keyword.get(options, :pipeline, Pipeline),
         pipeline_options:
           Keyword.merge(
             [
               test_observer: self(),
               jitter_latency: 0,
               track_id: Keyword.get(options, :track, @track).track_id
             ],
             Keyword.get(options, :pipeline_options, [])
           )}
      )

    assert :ok = RoomAudioIngress.start_pipeline(ingress)
    assert {:ok, _snapshot} = Authority.register_enforcer(authority, ingress)
    assert :ok = RoomAudioIngress.prepare_track(ingress, Keyword.get(options, :track, @track))

    pipeline_id =
      if Keyword.get(options, :pipeline, Pipeline) == Pipeline do
        assert_receive {:prepared_pipeline_started, pipeline, pipeline_id}
        assert :ok = Pipeline.ready(pipeline)
        pipeline_id
      end

    _ = :sys.get_state(ingress)
    assert {:ok, [_resource, decoder] = resources} = RoomAudioIngress.readiness_resources(ingress)

    initial =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: incarnation,
         attempt_id: connection,
         resources: resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: make_ref()
      )

    assert_receive {:vxpipe_readiness_changed, ^initial, %{status: :ready}}, 2_000

    %{
      ingress: ingress,
      authority: authority,
      candidate: candidate,
      destination: destination,
      pipeline: decoder.instance,
      pipeline_id: pipeline_id,
      incarnation: incarnation,
      connection: connection,
      observer: observer,
      receiver: receiver,
      tenant: plan.tenant_id,
      room: plan.room_id,
      caller: caller,
      clock: clock,
      options: [
        owner: self(),
        attempt_id: connection,
        deadline_ms: System.monotonic_time(:millisecond) + 5_000
      ]
    }
  end

  defp human,
    do: %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }

  defp collect(resources, context),
    do:
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: context.incarnation,
         attempt_id: context.connection,
         resources: resources,
         deadline_ms: Keyword.fetch!(context.options, :deadline_ms)},
        id: make_ref()
      )

  defp audio_frame(context, sequence),
    do: %AudioFrame{
      tenant_id: context.tenant,
      room_id: context.room,
      incarnation_id: context.incarnation,
      participant_id: context.caller,
      connection_id: context.connection,
      track_id: @track.track_id,
      codec: @track.codec,
      sample_rate: @track.sample_rate,
      channels: @track.channels,
      sequence_number: sequence,
      timestamp: sequence * 960,
      payload: <<1>>,
      received_at: 1_020
    }

  defp pcm_frame(context, timestamp),
    do: %PCMFrame{
      tenant_id: context.tenant,
      room_id: context.room,
      incarnation_id: context.incarnation,
      participant_id: context.caller,
      connection_id: context.connection,
      track_id: @track.track_id,
      timestamp: timestamp,
      sample_rate: 48_000,
      channels: 1,
      payload: <<0::16>>
    }
end
