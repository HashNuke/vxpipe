defmodule Vxpipe.Gateway.HTTP.HumanOnlyWebRTCTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Membrane.Opus.{Decoder, Encoder}
  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.{CallDefinition, CallInvocation, DefinitionCompiler}
  alias Vxpipe.CallEngine.Command.JoinParticipant
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.SessionSupervisor
  alias Vxpipe.Gateway.WebRTC.Connection

  @moduletag capture_log: true

  @application_voip 2_048
  @automatic_bitrate -1_000
  @endpoint_options Endpoint.init(cors: [])
  @signal_voice 3_001

  test "two admitted humans exchange live mix-minus audio over WebRTC" do
    plan = compile_plan()
    assert {:ok, room} = CallEngine.start_call(plan)
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

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "connected-media",
         resources: graph,
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
  end

  test "a receive-only connection can be ready without a negotiated input track" do
    plan = compile_monitor_plan()
    assert {:ok, room} = CallEngine.start_call(plan)
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
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    specialist = Map.fetch!(plan.participants, "specialist")

    caller_client = connect(issue_session(plan, room, caller.participant_id).session_id)
    receiver_client = connect(issue_session(plan, room, receiver.participant_id).session_id)

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
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    monitor = Map.fetch!(plan.participants, "monitor")

    caller_client = connect(issue_session(plan, room, caller.participant_id).session_id)
    receiver_client = connect(issue_session(plan, room, receiver.participant_id).session_id)

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
      schema_version: CallDefinition.schema_version(),
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

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-human-webrtc",
               actor_id: "actor-human-webrtc",
               call_id: unique_id("call-human-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())
    plan
  end

  defp compile_restrictive_plan do
    resource_id = unique_id("restrictive-webrtc")
    room_id = unique_id("room-restrictive-webrtc")

    input = %{
      schema_version: CallDefinition.schema_version(),
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

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-restrictive-webrtc",
               actor_id: "actor-restrictive-webrtc",
               call_id: unique_id("call-restrictive-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())
    plan
  end

  defp compile_monitor_plan do
    resource_id = unique_id("monitor-webrtc")
    room_id = unique_id("room-monitor-webrtc")

    input = %{
      schema_version: CallDefinition.schema_version(),
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

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-monitor-webrtc",
               actor_id: "actor-monitor-webrtc",
               call_id: unique_id("call-monitor-webrtc"),
               room_id: room_id
             )

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries())
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

  defp registries, do: %{capability_profiles: %{}, host_tools: %{}}

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
