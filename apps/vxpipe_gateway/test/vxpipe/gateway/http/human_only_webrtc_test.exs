defmodule Vxpipe.Gateway.HTTP.HumanOnlyWebRTCTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Membrane.Opus.{Decoder, Encoder}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.SessionSupervisor
  alias Vxpipe.Gateway.WebRTC.Connection

  @moduletag capture_log: true

  @application_voip 2_048
  @automatic_bitrate -1_000
  @endpoint_options Endpoint.init(cors: [])
  @signal_voice 3_001

  test "prepares the complete prospective room before opening changed participant routes" do
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.{Collector, Preparation}
    alias Vxpipe.Gateway.Media.{OutputArbiter, RoomAudioEgress}

    plan = compile_restrictive_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)
    specialist = Map.fetch!(plan.participants, "specialist").participant_id
    assert {:ok, command} = join_command(plan, specialist)
    assert {:ok, _participant} = CallEngine.join_participant(command)

    clients =
      Map.new(["caller", "receiver", "specialist"], fn key ->
        participant = Map.fetch!(plan.participants, key).participant_id
        {key, connect(issue_session(plan, room, participant).session_id)}
      end)

    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    refute_audio(Map.fetch!(clients, "receiver"), 40)

    transports =
      Enum.map(clients, fn {_key, client} ->
        assert {:ok, resource, _status} = Connection.readiness(client.connection_id)
        resource
      end)

    initial =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "room-transports",
         resources: transports,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: :room_transports
      )

    assert_receive {:vxpipe_readiness_changed, ^initial, %{status: :ready}}, 2_000

    bindings =
      Map.new(["caller", "receiver"], fn key ->
        client = Map.fetch!(clients, key)
        assert {:ok, resource, :ready} = Connection.readiness(client.connection_id)
        assert {:ok, binding} = GenServer.call(resource.instance, :vxpipe_connection_readiness)
        assert :ok = RoomAudioEgress.hold(binding.room_output, 1)
        {key, binding}
      end)

    native =
      Map.new(bindings, fn {key, binding} ->
        assert {:ok, resources} = OutputArbiter.readiness_resources(binding.output)
        {key, resources}
      end)

    authority = Authority.whereis(room.incarnation_id)
    base = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.delete(base.present_participant_ids, specialist)
             )

    [{room_authority, _}] =
      Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    options = [
      owner: self(),
      attempt_id: "whole-room-candidate",
      generation: 1,
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    assert {:ok, prepared} = Preparation.run_candidate(room_authority, candidate, options)
    assert map_size(prepared.connections) == 2
    assert Enum.count(prepared.resources, &(&1.kind == :media_connection)) == 2
    assert Enum.any?(prepared.resources, &(&1.kind == :transcript_router))
    assert Enum.any?(prepared.resources, &(&1.kind == :room_mixer))
    assert Enum.any?(prepared.resources, &(&1.kind == :call_variables))
    refute Enum.any?(prepared.resources, &(&1.scope == {:participant, specialist}))
    assert Authority.snapshot(authority) == base
    prepared_router = Enum.find(prepared.resources, &(&1.kind == :transcript_router))
    assert :ok = Preparation.discard(prepared)
    assert {:error, :unavailable} = CallEngine.TranscriptRouter.readiness_binding(prepared_router)
    assert Authority.snapshot(authority) == base
    assert {:ok, prepared} = Preparation.run_candidate(room_authority, candidate, options)
    router = CallEngine.TranscriptRouter.whereis(room.incarnation_id)
    caller_id = Map.fetch!(plan.participants, "caller").participant_id
    receiver_id = Map.fetch!(plan.participants, "receiver").participant_id
    recipients = MapSet.new([receiver_id])

    assert {:ok, before} =
             CallEngine.TranscriptRouter.project_current(router, caller_id, recipients)

    assert before.recipient_participant_ids == MapSet.new()

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "whole-room-candidate",
         resources: prepared.resources,
         deadline_ms: Keyword.fetch!(options, :deadline_ms)},
        id: :whole_room
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert {:ok, ^prepared} = Preparation.run_candidate(room_authority, candidate, options)
    assert {:ok, installed} = Authority.leave(authority, specialist)
    assert installed == candidate.snapshot

    assert {:ok, after_commit} =
             CallEngine.TranscriptRouter.project_current(router, caller_id, recipients)

    assert after_commit.recipient_participant_ids == recipients

    for resource <- prepared.resources do
      result =
        if function_exported?(resource.adapter, :readiness_binding, 1),
          do: resource.adapter.readiness_binding(resource),
          else: resource.adapter.readiness(resource.instance)

      assert {:ok, ^resource, :ready} = result
    end

    assert :ok = Preparation.discard(prepared)

    for {key, binding} <- bindings do
      expected = Map.fetch!(native, key)
      assert {:ok, ^expected} = OutputArbiter.readiness_resources(binding.output)
      assert :ok = RoomAudioEgress.release(binding.room_output, 1)
    end

    :ok = send_audio(Map.fetch!(clients, "caller"), 1, 960, 8_000)

    assert clients |> Map.fetch!("receiver") |> await_audio(5_000) |> decodable_pcm_size() ==
             1_920
  end

  test "collects and adopts a prospective connection graph without replacing unaffected output" do
    alias Vxpipe.CallEngine.Media.ConnectionReadiness
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Collector
    alias Vxpipe.CallEngine.RoomMixer
    alias Vxpipe.Gateway.Media.{OutputArbiter, RoomAudioEgress, RoomAudioIngress}

    plan = compile_restrictive_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)
    caller = Map.fetch!(plan.participants, "caller")
    receiver = Map.fetch!(plan.participants, "receiver")
    specialist = Map.fetch!(plan.participants, "specialist")
    client = connect(issue_session(plan, room, caller.participant_id).session_id)
    receiver_client = connect(issue_session(plan, room, receiver.participant_id).session_id)
    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    refute_audio(receiver_client, 40)

    assert {:ok, receiver_transport, _status} =
             Connection.readiness(receiver_client.connection_id)

    assert {:ok, transport, _status} = Connection.readiness(client.connection_id)

    transports =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "web-transports",
         resources: [transport, receiver_transport],
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: :transport_collector
      )

    assert_receive {:vxpipe_readiness_changed, ^transports, %{status: :ready}}, 2_000

    assert {:ok, receiver_binding} =
             GenServer.call(receiver_transport.instance, :vxpipe_connection_readiness)

    assert {:ok, binding} = GenServer.call(transport.instance, :vxpipe_connection_readiness)
    authority = Authority.whereis(room.incarnation_id)
    base = Authority.snapshot(authority)
    demand = [audio_input?: true, room_output?: true]

    assert {:ok, initial} =
             ConnectionReadiness.prepare_graph(transport.instance, binding.identity, base, demand)

    initial_collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "initial-web",
         resources: initial.resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: :initial_collector
      )

    assert_receive {:vxpipe_readiness_changed, ^initial_collector, %{status: :ready}}, 2_000

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(base.present_participant_ids, specialist.participant_id)
             )

    assert :ok = RoomAudioEgress.hold(binding.room_output, 1)
    assert {:ok, live_input, :ready} = RoomAudioIngress.readiness(binding.room_input)
    assert {:ok, native} = OutputArbiter.readiness_resources(binding.output)

    options = [
      owner: self(),
      attempt_id: "candidate-web",
      generation: 1,
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    subscription_options =
      Map.to_list(binding.identity) ++
        [
          id: client.connection_id <> ":room-output",
          recipient_participant_id: caller.participant_id,
          subscriber: binding.room_output,
          mode: :mix_minus
        ]

    assert {:ok, mixer} =
             RoomMixer.prepare_policy(
               RoomMixer.whereis(room.incarnation_id),
               candidate,
               Keyword.put(options, :subscriptions, [subscription_options])
             )

    subscription = Map.fetch!(mixer.subscriptions, client.connection_id <> ":room-output")
    options = Keyword.put(options, :subscription, subscription)

    assert :ok = RoomAudioEgress.hold(receiver_binding.room_output, 1)

    assert {:ok, removed_input} =
             ConnectionReadiness.prepare_candidate(
               receiver_transport.instance,
               receiver_binding.identity,
               candidate,
               [],
               Keyword.delete(options, :subscription)
             )

    assert removed_input.input_track == nil
    refute Enum.any?(removed_input.resources, &(&1.kind in [:room_audio_ingress, :audio_input]))

    assert {:ok, graph} =
             ConnectionReadiness.prepare_candidate(
               transport.instance,
               binding.identity,
               candidate,
               demand,
               options
             )

    assert Authority.snapshot(authority) == base
    assert {:ok, ^live_input, :ready} = RoomAudioIngress.readiness(binding.room_input)
    assert {:ok, ^native} = OutputArbiter.readiness_resources(binding.output)

    assert {:ok, ^graph} =
             ConnectionReadiness.prepare_candidate(
               transport.instance,
               binding.identity,
               candidate,
               demand,
               options
             )

    decoder = Enum.find(graph.resources, &(&1.kind == :audio_input))
    monitor = Process.monitor(decoder.instance)
    assert :ok = ConnectionReadiness.discard_candidate(graph)
    assert_receive {:DOWN, ^monitor, :process, _decoder, _reason}, 1_000
    assert {:ok, ^live_input, :ready} = RoomAudioIngress.readiness(binding.room_input)
    assert {:ok, ^native} = OutputArbiter.readiness_resources(binding.output)

    assert {:ok, graph} =
             ConnectionReadiness.prepare_candidate(
               transport.instance,
               binding.identity,
               candidate,
               demand,
               options
             )

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "candidate-web",
         resources: graph.resources,
         deadline_ms: Keyword.fetch!(options, :deadline_ms)}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert {:ok, command} = join_command(plan, specialist.participant_id)
    assert {:ok, _participant} = CallEngine.join_participant(command)
    assert Authority.snapshot(authority) == candidate.snapshot

    assert {:ok, [_input_actor]} =
             RoomAudioIngress.readiness_resources(receiver_binding.room_input)

    for resource <- graph.resources do
      result =
        if function_exported?(resource.adapter, :readiness_binding, 1),
          do: resource.adapter.readiness_binding(resource),
          else: resource.adapter.readiness(resource.instance)

      assert {:ok, ^resource, :ready} = result
    end

    assert {:ok, ^native} = OutputArbiter.readiness_resources(binding.output)
    assert :ok = ConnectionReadiness.discard_candidate(graph)
    assert :ok = RoomAudioEgress.release(binding.room_output, 1)
    specialist_client = connect(issue_session(plan, room, specialist.participant_id).session_id)
    :ok = send_audio(client, 1, 960, 8_000)
    assert specialist_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920
  end

  test "two admitted humans exchange live mix-minus audio over WebRTC" do
    plan = compile_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    caller_session = issue_session(plan, room, caller.participant_id)
    receiver_session = issue_session(plan, room, receiver.participant_id)

    caller_client =
      connect(caller_session.session_id,
        before_connect: fn connection ->
          assert {:ok, _output, :preparing} = Connection.readiness(connection)
          assert {:ok, _input, :preparing} = Connection.input_readiness(connection)
        end
      )

    receiver_client = connect(receiver_session.session_id)
    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    refute_audio(receiver_client, 40)

    assert {:ok, [output, input]} =
             Connection.readiness_resources(caller_client.connection_id, input?: true)

    assert output.kind == :media_connection
    assert input.kind == :media_input
    assert input.scope == {:participant, caller.participant_id}

    assert {:ok, graph} =
             prepare_media(
               output.instance,
               plan,
               room,
               caller.participant_id,
               caller_client.connection_id,
               audio_input?: true,
               room_output?: true
             )

    assert MapSet.new(graph, & &1.kind) ==
             MapSet.new([
               :media_connection,
               :media_input,
               :private_output,
               :audio_output,
               :room_audio_ingress,
               :audio_input,
               :room_audio_egress,
               :audio_subscription,
               :room_output_binding
             ])

    assert {:ok, binding} = GenServer.call(output.instance, :vxpipe_connection_readiness)

    current_policy =
      room.incarnation_id
      |> Vxpipe.CallEngine.MediaPolicy.Authority.whereis()
      |> Vxpipe.CallEngine.MediaPolicy.Authority.snapshot()

    assert {:ok, candidate_policy} =
             Vxpipe.CallEngine.MediaPolicy.Snapshot.prepare(
               %{
                 current_policy
                 | revision: current_policy.revision + 1,
                   effective: %{current_policy.effective | record_audio: false}
               },
               current_policy
             )

    assert {:error, :policy_not_prepared} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare(
               output.instance,
               binding.identity,
               candidate_policy,
               audio_input?: true,
               room_output?: true
             )

    policy_authority = Vxpipe.CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)

    assert {:ok, candidate} =
             Vxpipe.CallEngine.MediaPolicy.Authority.preview_presence(
               policy_authority,
               current_policy.present_participant_ids
             )

    [{room_authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, prepared_room} =
             Vxpipe.CallEngine.Readiness.Preparation.run(room_authority, candidate)

    assert map_size(prepared_room.connections) == 2
    assert length(prepared_room.resources) == 22
    assert MapSet.subset?(MapSet.new(graph), MapSet.new(prepared_room.resources))

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "connected-media",
         resources: prepared_room.resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, ^output, :ready} = Connection.readiness(caller_client.connection_id)
    assert {:ok, ^input, :ready} = Connection.input_readiness(caller_client.connection_id)
    assert {:ok, track} = Connection.input_track(caller_client.connection_id)
    assert track.codec == :opus
    assert track.sample_rate == 48_000
    assert is_binary(track.track_id)

    assert {:ok, preparation} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare_graph(
               output.instance,
               binding.identity,
               current_policy,
               audio_input?: true,
               room_output?: true
             )

    assert preparation.resources == graph
    assert preparation.input_track == track
    assert preparation.identity == binding.identity

    :ok = send_audio(caller_client, 1, 960, 8_000)
    receiver_packet = await_audio(receiver_client, 5_000)
    assert decodable_pcm_size(receiver_packet) == 1_920
    caller_peer = caller_client.client
    caller_output_track_id = caller_client.output_track_id

    refute_receive {:ex_webrtc, ^caller_peer, {:rtp, ^caller_output_track_id, _rid, %Packet{}}},
                   500

    :ok = send_audio(receiver_client, 1, 960, -8_000)
    caller_packet = await_audio(caller_client, 5_000)
    assert decodable_pcm_size(caller_packet) == 1_920
    assert {:ok, ^output, :ready} = Connection.readiness(caller_client.connection_id)
    assert {:ok, ^input, :ready} = Connection.input_readiness(caller_client.connection_id)
    assert {:ok, ^track} = Connection.input_track(caller_client.connection_id)

    assert {:ok, ^graph} =
             prepare_media(
               output.instance,
               plan,
               room,
               caller.participant_id,
               caller_client.connection_id,
               audio_input?: true,
               room_output?: true
             )

    assert {:ok, repeated_room} =
             Vxpipe.CallEngine.Readiness.Preparation.run(room_authority, candidate)

    assert repeated_room.resources == prepared_room.resources
  end

  test "a receive-only connection can be ready without a negotiated input track" do
    plan = compile_monitor_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)
    monitor = Map.fetch!(plan.participants, "monitor")
    assert {:ok, command} = join_command(plan, monitor.participant_id, :monitor)
    assert {:ok, _participant} = CallEngine.join_participant(command)

    client =
      connect(issue_session(plan, room, monitor.participant_id).session_id, direction: :recvonly)

    assert {:ok, [output]} = Connection.readiness_resources(client.connection_id)

    assert {:ok, graph} =
             prepare_media(
               output.instance,
               plan,
               room,
               monitor.participant_id,
               client.connection_id,
               room_output?: true
             )

    assert MapSet.new(graph, & &1.kind) ==
             MapSet.new([
               :media_connection,
               :private_output,
               :audio_output,
               :room_audio_egress,
               :audio_subscription,
               :room_output_binding
             ])

    assert {:error, :input_not_admitted} =
             prepare_media(
               output.instance,
               plan,
               room,
               monitor.participant_id,
               client.connection_id,
               audio_input?: true
             )

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "receive-only-media",
         resources: graph,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert {:ok, ^output, :ready} = Connection.readiness(client.connection_id)
    assert {:ok, input, :preparing} = Connection.input_readiness(client.connection_id)
    assert input.scope == {:participant, monitor.participant_id}
    assert {:error, :unavailable} = Connection.input_track(client.connection_id)
  end

  test "a restrictive participant commits new live routes before queued audio can cross" do
    plan = compile_restrictive_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    specialist = Map.fetch!(plan.participants, "specialist")

    caller_client = connect(issue_session(plan, room, caller.participant_id).session_id)
    receiver_client = connect(issue_session(plan, room, receiver.participant_id).session_id)
    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    refute_audio(receiver_client, 40)

    :ok = send_audio(caller_client, 1, 960, 8_000)
    assert receiver_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    :ok = send_audio(caller_client, 2, 1_920, 7_000)
    assert {:ok, command} = join_command(plan, specialist.participant_id)
    assert {:ok, _participant} = CallEngine.join_participant(command)

    specialist_client =
      plan
      |> issue_session(room, specialist.participant_id)
      |> then(&connect(&1.session_id))

    receiver_peer = receiver_client.client
    receiver_track = receiver_client.output_track_id

    refute_receive {:ex_webrtc, ^receiver_peer, {:rtp, ^receiver_track, _rid, %Packet{}}},
                   1_000

    :ok = send_audio(caller_client, 3, 2_880, 6_000)
    assert specialist_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    :ok = send_audio(specialist_client, 1, 960, -6_000)
    assert caller_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    refute_receive {:ex_webrtc, ^receiver_peer, {:rtp, ^receiver_track, _rid, %Packet{}}},
                   500
  end

  test "an authorized silent monitor hears permitted WebRTC sources and cannot publish" do
    plan = compile_monitor_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    monitor = Map.fetch!(plan.participants, "monitor")

    caller_client = connect(issue_session(plan, room, caller.participant_id).session_id)
    receiver_client = connect(issue_session(plan, room, receiver.participant_id).session_id)
    Vxpipe.CallEngine.TestCallStartup.await_open(plan)
    refute_audio(receiver_client, 40)

    assert {:ok, command} = join_command(plan, monitor.participant_id, :monitor)
    assert {:ok, _participant} = CallEngine.join_participant(command)

    monitor_client = connect(issue_session(plan, room, monitor.participant_id).session_id)

    :ok = send_audio(caller_client, 1, 960, 8_000)
    assert receiver_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920
    assert monitor_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    :ok = send_audio(receiver_client, 1, 960, -8_000)
    assert caller_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920
    refute_audio(monitor_client, 500)

    :ok = send_audio(monitor_client, 1, 960, 5_000)
    refute_audio(caller_client, 500)
    refute_audio(receiver_client, 500)
    assert :ok = Connection.add_ice_candidates(monitor_client.connection_id, [])
  end

  defp prepare_media(connection, plan, room, participant_id, connection_id, demand) do
    alias Vxpipe.CallEngine.MediaPolicy.Authority

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant_id,
      connection_id: connection_id
    }

    policy = room.incarnation_id |> Authority.whereis() |> Authority.snapshot()
    Vxpipe.CallEngine.Media.ConnectionReadiness.prepare(connection, identity, policy, demand)
  end

  defp compile_plan do
    resource_id = unique_id("human-webrtc")
    room_id = unique_id("room-human-webrtc")

    input = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant()
      },
      limits: %{max_duration_ms: 30_000}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-webrtc",
               actor_id: "actor-human-webrtc",
               call_id: unique_id("call-human-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    plan
  end

  defp compile_restrictive_plan do
    resource_id = unique_id("restrictive-webrtc")
    room_id = unique_id("room-restrictive-webrtc")

    input = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant(),
        "specialist" =>
          Map.put(human_participant(), :while_present, %{
            audio_routes: %{
              "caller" => ["specialist"],
              "specialist" => ["caller"]
            },
            transcript_routes: %{
              "caller" => ["specialist"],
              "specialist" => ["caller"]
            },
            record_audio: false,
            save_transcripts: false
          })
      },
      limits: %{max_duration_ms: 30_000}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-restrictive-webrtc",
               actor_id: "actor-restrictive-webrtc",
               call_id: unique_id("call-restrictive-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    plan
  end

  defp compile_monitor_plan do
    resource_id = unique_id("monitor-webrtc")
    room_id = unique_id("room-monitor-webrtc")

    input = %{
      schema_version: CallSpec.schema_version(),
      wait_sounds: %{call_setup: nil},
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      media_policy: %{
        audio_routes: %{
          "caller" => ["receiver", "monitor"],
          "receiver" => ["caller"],
          "monitor" => []
        }
      },
      participants: %{
        "caller" => human_participant(),
        "receiver" => human_participant(),
        "monitor" => human_participant()
      },
      limits: %{max_duration_ms: 30_000}
    }

    assert {:ok, call_spec} =
             CallSpec.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-monitor-webrtc",
               actor_id: "actor-monitor-webrtc",
               call_id: unique_id("call-monitor-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = CallSpecCompiler.compile(call_spec, invocation, registries())
    plan
  end

  defp join_command(plan, participant_id, role \\ :human) do
    JoinParticipant.new(
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      participant_id: participant_id,
      role: role,
      deadline: DateTime.add(DateTime.utc_now(), 5, :second)
    )
  end

  defp human_participant do
    %{
      type: "human",
      connection: %{service: "web", mode: "receive", admission: "start_call"},
      capabilities: %{}
    }
  end

  defp registries, do: %{host_tools: %{}}

  defp issue_session(plan, room, participant_id) do
    binding = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant_id,
      tool_visibility: plan.tool_visibility
    ]

    assert {:ok, session} = SessionSupervisor.issue(binding, 30_000)
    session
  end

  defp connect(session_id, options \\ []) do
    client_id = unique_id("client")
    child_spec = Supervisor.child_spec({PeerConnection, []}, id: {PeerConnection, client_id})
    client = start_supervised!(child_spec)
    :ok = PeerConnection.controlling_process(client, self())

    input_track = MediaStreamTrack.new(:audio)

    assert {:ok, _transceiver} =
             PeerConnection.add_transceiver(client, input_track,
               direction: Keyword.get(options, :direction, :sendrecv)
             )

    assert {:ok, offer} = PeerConnection.create_offer(client)
    :ok = PeerConnection.set_local_description(client, offer)

    response =
      :post
      |> conn(
        "/api/rtvi/offer",
        JSON.encode!(%{
          "sdp" => offer.sdp,
          "type" => "offer",
          "pc_id" => nil,
          "restart_pc" => false,
          "requestData" => %{"session_id" => session_id}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert response.status == 200

    assert %{"pc_id" => connection_id, "sdp" => answer_sdp, "type" => "answer"} =
             JSON.decode!(response.resp_body)

    if callback = Keyword.get(options, :before_connect), do: callback.(connection_id)

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client, {:ice_candidate, %ICECandidate{} = candidate}}, 5_000
    patch_candidate(connection_id, candidate)
    assert_receive {:ex_webrtc, ^client, {:connection_state_change, :connected}}, 5_000

    assert_receive {:ex_webrtc, ^client,
                    {:track, %MediaStreamTrack{kind: :audio} = output_track}},
                   5_000

    %{
      client: client,
      connection_id: connection_id,
      input_track_id: input_track.id,
      output_track_id: output_track.id
    }
  end

  defp patch_candidate(connection_id, candidate) do
    response =
      :patch
      |> conn(
        "/api/rtvi/offer",
        JSON.encode!(%{
          "pc_id" => connection_id,
          "candidates" => [
            %{
              "candidate" => candidate.candidate,
              "sdp_mid" => candidate.sdp_mid,
              "sdp_mline_index" => candidate.sdp_m_line_index
            }
          ]
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(@endpoint_options)

    assert response.status == 200
  end

  defp send_audio(connection, sequence_number, timestamp, sample) do
    encoder =
      Encoder.Native.create(
        48_000,
        1,
        @application_voip,
        @automatic_bitrate,
        @signal_voice
      )

    pcm = :binary.copy(<<sample::little-signed-16>>, 960)
    assert {:ok, payload} = Encoder.Native.encode_packet(encoder, pcm, 960)

    packet =
      Packet.new(payload,
        payload_type: 111,
        sequence_number: sequence_number,
        timestamp: timestamp,
        ssrc: 123
      )

    PeerConnection.send_rtp(connection.client, connection.input_track_id, packet)
  end

  defp await_audio(connection, timeout_ms) do
    receive do
      {:ex_webrtc, client, {:rtp, track_id, _rid, %Packet{} = packet}}
      when client == connection.client and track_id == connection.output_track_id ->
        packet
    after
      timeout_ms -> flunk("timed out waiting for mixed WebRTC audio")
    end
  end

  defp refute_audio(connection, timeout_ms) do
    client = connection.client
    output_track_id = connection.output_track_id

    refute_receive {:ex_webrtc, ^client, {:rtp, ^output_track_id, _rid, %Packet{}}}, timeout_ms
  end

  defp decodable_pcm_size(packet) do
    decoder = Decoder.Native.create(48_000, 1)
    packet |> then(&Decoder.Native.decode_packet(decoder, &1.payload)) |> byte_size()
  end

  defp stop_room_on_exit(plan) do
    on_exit(fn ->
      case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) do
        [{room, _value}] -> GenServer.stop(room, :shutdown)
        [] -> :ok
      end
    end)
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
