defmodule Vxpipe.Gateway.HTTP.HumanTransferWebRTCTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias ExRTP.Packet
  alias ExWebRTC.{DataChannel, ICECandidate, MediaStreamTrack, PeerConnection, SessionDescription}
  alias Membrane.Opus.{Decoder, Encoder}
  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestSelectiveAgentRuntimeModelProvider,
    TestTextToSpeechTransport,
    TestSpeechToTextTransport
  }

  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.SessionSupervisor

  @moduletag capture_log: true

  @application_voip 2_048
  @automatic_bitrate -1_000
  @endpoint_options Endpoint.init(cors: [])
  @signal_voice 3_001

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestSelectiveAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [api_key: "runtime-test-secret"],
      transport: {TestSpeechToTextTransport, observer: self()},
      media_ingress: [
        maximum_frames: 50,
        maximum_bytes: 65_536,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 10
      ]
    ]

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-test-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, observer: self()},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:agent_runtime, agent_runtime)
      |> Keyword.put(:text_to_speech, text_to_speech)
      |> Keyword.put(:speech_to_text, speech_to_text)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "a destination accepts privately before joining bidirectional room audio" do
    plan = compile_plan()

    assert {:ok, room} =
             CallEngine.start_call(plan,
               recording: [
                 enabled: true,
                 targets: [:individual_tracks],
                 writer: {Vxpipe.CallEngine.TestRecordingWriter, observer: self()},
                 maximum_pull_frames: 20
               ]
             )

    stop_room_on_exit(plan)

    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")

    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    caller_client =
      plan
      |> issue_session(room, caller.participant_id)
      |> then(&connect(&1.session_id, "chat"))

    authority = Vxpipe.CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)
    policy = Vxpipe.CallEngine.MediaPolicy.Authority.snapshot(authority)

    assert {:ok, candidate} =
             Vxpipe.CallEngine.MediaPolicy.Authority.preview_presence(
               authority,
               policy.present_participant_ids
             )

    [{room_authority, _}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, prepared_room} =
             Vxpipe.CallEngine.Readiness.Preparation.run(room_authority, candidate)

    assert Enum.any?(prepared_room.resources, &(&1.kind == :model_inference))
    assert Enum.any?(prepared_room.resources, &(&1.kind == :text_to_speech))
    assert Enum.any?(prepared_room.resources, &(&1.kind == :recording_output))
    caller_id = caller.participant_id
    agent_id = Map.fetch!(plan.participants, plan.entry_receiver).participant_id

    assert_receive {:test_recording_writer_opened, _worker, _recorder,
                    %{participant_id: ^caller_id}},
                   1_000

    assert_receive {:test_recording_writer_opened, _worker, _recorder,
                    %{participant_id: ^agent_id, track_id: "agent-egress"}},
                   1_000

    readiness =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "initial-room",
         resources: prepared_room.resources,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000},
        id: :initial_room_readiness
      )

    assert_receive {:vxpipe_readiness_changed, ^readiness,
                    %{status: :preparing, blockers: [%{kind: :text_to_speech}]}},
                   1_000

    refute_receive {:vxpipe_readiness_changed, ^readiness, %{status: :ready}}

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    assert :ok = Vxpipe.CallEngine.Readiness.Collector.refresh(readiness)
    assert_receive {:vxpipe_readiness_changed, ^readiness, %{status: :ready}}, 1_000
    stop_supervised!(:initial_room_readiness)

    assert :ok = send_rtvi_text(caller_client)
    assert_receive {:test_agent_runtime_stream, source_provider, _request}, 2_000

    reason = "Taylor is calling about order 17."

    assert {:ok, transfer_call} =
             ToolCall.new(
               id: "human-support-transfer",
               name: "transfer",
               arguments: %{"destination" => "human-support", "reason" => reason}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer_call])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_transport_started, briefing_tts, _connection}, 2_000

    support_client =
      plan
      |> issue_session(room, support.participant_id)
      |> then(&connect(&1.session_id, "vxpipe"))

    assert %{
             "id" => attempt_id,
             "type" => "transfer.preparation",
             "data" => %{
               "attempt_id" => attempt_id,
               "participant_id" => participant_id
             }
           } = await_sideband(support_client, "transfer.preparation", 5_000)

    assert participant_id == support.participant_id

    caller_audio_started_at = System.monotonic_time(:millisecond)
    :ok = send_audio(caller_client, 1, 960, 8_000)
    refute_audio(support_client, 500)

    :ok = send_audio(support_client, 1, 960, -8_000)
    refute_audio(caller_client, 500)

    :ok = send_acceptance(support_client, "accept-stale", "xfer-stale")

    assert %{
             "id" => "accept-stale",
             "type" => "error",
             "data" => %{"message" => "The transfer control could not be accepted."}
           } = await_sideband(support_client, "error", 5_000)

    refute_receive {:test_stt_transport_started, _, _}
    :ok = send_acceptance(support_client, "accept-support", attempt_id)

    assert_receive {:test_tts_control, ^briefing_tts, speak}, 2_000

    assert JSON.decode!(speak) == %{
             "text" => reason <> " This call is recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"private-briefing"})
    )

    TestTextToSpeechTransport.deliver_audio(briefing_tts, :binary.copy(<<1, 0>>, 960))

    TestTextToSpeechTransport.deliver_control(
      briefing_tts,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"private-briefing"})
    )

    assert support_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    assert %{
             "id" => ^attempt_id,
             "type" => "transfer.active",
             "data" => %{"attempt_id" => ^attempt_id}
           } = await_sideband(support_client, "transfer.active", 5_000)

    assert_receive {:test_stt_transport_started, support_stt, _connection}, 2_000

    assert {:ok, output, :ready} =
             Vxpipe.Gateway.WebRTC.Connection.readiness(support_client.connection_id)

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: support.participant_id,
      connection_id: support_client.connection_id
    }

    policy =
      room.incarnation_id
      |> Vxpipe.CallEngine.MediaPolicy.Authority.whereis()
      |> Vxpipe.CallEngine.MediaPolicy.Authority.snapshot()

    assert {:ok, graph} =
             Vxpipe.CallEngine.Media.ConnectionReadiness.prepare(
               output.instance,
               identity,
               policy,
               audio_input?: true,
               room_output?: true,
               speech_to_text?: true
             )

    assert Enum.any?(graph, &(&1.kind == :speech_to_text_ingress))
    assert Enum.any?(graph, &(&1.kind == :speech_to_text))

    collector =
      start_supervised!(
        {Vxpipe.CallEngine.Readiness.Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: attempt_id,
         resources: graph,
         deadline_ms: System.monotonic_time(:millisecond) + 5_000}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector,
                    %{status: :preparing, blockers: blockers}},
                   2_000

    assert Enum.any?(blockers, &(&1.kind == :speech_to_text))
    refute_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    TestSpeechToTextTransport.deliver(
      support_stt,
      ~s({"type":"Connected","request_id":"support-request","sequence_id":0})
    )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000

    verify_prepared_speech_graph(output.instance, identity, graph, policy, plan, room)

    # RTP time advances during the private briefing even when this fixture is silent.
    # The unchanged caller normalizer retains its original clock alignment.
    elapsed_ms = System.monotonic_time(:millisecond) - caller_audio_started_at
    caller_timestamp = 960 + div(elapsed_ms, 20) * 960
    :ok = send_audio(caller_client, 2, caller_timestamp, 7_000)
    assert support_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

    Enum.each(
      [{2, 1_920}, {3, 2_880}, {4, 3_840}],
      fn {sequence_number, timestamp} ->
        :ok = send_audio(support_client, sequence_number, timestamp, -7_000)
      end
    )

    assert caller_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920
    assert_receive {:test_stt_audio, ^support_stt, _audio}, 2_000

    for {event, sequence} <- [{"StartOfTurn", 1}, {"EndOfTurn", 2}] do
      TestSpeechToTextTransport.deliver(
        support_stt,
        JSON.encode!(%{
          "type" => "TurnInfo",
          "request_id" => "support-request",
          "sequence_id" => sequence,
          "event" => event,
          "turn_index" => 0,
          "audio_window_start" => 0.0,
          "audio_window_end" => 1.0,
          "transcript" => "Human support is here.",
          "words" => [],
          "end_of_turn_confidence" => 0.8,
          "trigger" => "model"
        })
      )
    end

    support_id = support.participant_id

    assert %{
             "data" => %{
               "text" => "Human support is here.",
               "user_id" => ^support_id,
               "final" => false
             }
           } =
             await_sideband(caller_client, "user-transcription", 5_000)

    assert %{
             "data" => %{
               "text" => "Human support is here.",
               "user_id" => ^support_id,
               "final" => true
             }
           } =
             await_sideband(caller_client, "user-transcription", 5_000)
  end

  test "prepares the complete agent recording path before relaxing recording permission" do
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.{Collector, Preparation}
    alias Vxpipe.Gateway.Media.RoomAudioEgress

    plan = compile_plan()

    assert {:ok, room} =
             CallEngine.start_call(plan,
               recording: [
                 enabled: true,
                 targets: [:individual_tracks],
                 writer: {CallEngine.TestRecordingWriter, observer: self()},
                 maximum_pull_frames: 20
               ]
             )

    stop_room_on_exit(plan)
    caller = Map.fetch!(plan.participants, "caller")
    assert_receive {:test_tts_transport_started, source_tts, _connection}, 2_000

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    _client =
      plan |> issue_session(room, caller.participant_id) |> then(&connect(&1.session_id, "chat"))

    [{room_authority, _}] =
      Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, room_binding} = CallEngine.RoomAuthority.readiness_binding(room_authority)
    [connection] = Map.values(room_binding.connections)
    assert {:ok, binding} = GenServer.call(connection.pid, :vxpipe_connection_readiness)
    assert :ok = RoomAudioEgress.hold(binding.room_output, 1)
    authority = Authority.whereis(room.incarnation_id)
    restricted = Map.fetch!(plan.participants, "recording-restriction").participant_id
    assert {:ok, denied} = Authority.admit(authority, restricted)

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.delete(denied.present_participant_ids, restricted)
             )

    options = [
      owner: self(),
      attempt_id: "agent-recording-policy",
      generation: 1,
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    assert {:ok, prepared} = Preparation.run_candidate(room_authority, candidate, options)
    taps = Enum.filter(prepared.resources, &(&1.kind == :recording_output))
    assert length(taps) == 1
    assert Enum.count(prepared.resources, &(&1.kind == :recording_writer)) == 2
    assert Authority.snapshot(authority) == denied

    collector =
      start_supervised!(
        {Collector,
         Keyword.merge(options,
           incarnation_id: room.incarnation_id,
           resources: prepared.resources
         )}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert :ok = Preparation.discard(prepared)
    stop_supervised!({Collector, "agent-recording-policy"})
    assert {:ok, retry} = Preparation.run_candidate(room_authority, candidate, options)
    assert Enum.filter(retry.resources, &(&1.kind == :recording_output)) == taps

    collector =
      start_supervised!(
        {Collector,
         Keyword.merge(options, incarnation_id: room.incarnation_id, resources: retry.resources)}
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000

    assert {:ok, snapshot} =
             Authority.commit_candidate(
               authority,
               candidate,
               Keyword.fetch!(options, :deadline_ms)
             )

    assert snapshot == candidate.snapshot

    assert :ok = Collector.refresh(collector)
    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000

    assert :ok = RoomAudioEgress.release(binding.room_output, 1)
    refute_receive {:test_tts_transport_started, _replacement, _connection}
  end

  defp verify_prepared_speech_graph(connection, identity, current, policy, plan, room) do
    alias Vxpipe.CallEngine.Capability.SpeechToText
    alias Vxpipe.CallEngine.Media.ConnectionReadiness
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Collector
    alias Vxpipe.CallEngine.RoomMixer
    alias Vxpipe.Gateway.Media.RoomAudioEgress

    assert {:ok, binding} = GenServer.call(connection, :vxpipe_connection_readiness)
    authority = Authority.whereis(room.incarnation_id)
    observer = Map.fetch!(plan.participants, "observer").participant_id

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.put(policy.present_participant_ids, observer)
             )

    assert :ok = RoomAudioEgress.hold(binding.room_output, 1)

    options = [
      owner: self(),
      attempt_id: "candidate-speech",
      generation: 1,
      deadline_ms: System.monotonic_time(:millisecond) + 5_000
    ]

    speech = Enum.find(current, &(&1.kind == :speech_to_text))

    assert {:ok, prepared_speech} =
             SpeechToText.prepare_policy(speech.instance, candidate, options)

    assert prepared_speech.change == :replace
    assert [provider] = prepared_speech.resources
    assert_receive {:test_stt_transport_started, replacement, _connection}, 1_000

    subscription =
      Map.to_list(identity) ++
        [
          id: identity.connection_id <> ":room-output",
          recipient_participant_id: identity.participant_id,
          subscriber: binding.room_output,
          mode: :mix_minus
        ]

    mixer = RoomMixer.whereis(room.incarnation_id)

    assert {:ok, prepared_mixer} =
             RoomMixer.prepare_policy(
               mixer,
               candidate,
               Keyword.put(options, :subscriptions, [subscription])
             )

    handle = Map.fetch!(prepared_mixer.subscriptions, identity.connection_id <> ":room-output")

    options =
      options |> Keyword.put(:subscription, handle) |> Keyword.put(:speech_to_text, provider)

    assert {:ok, graph} =
             ConnectionReadiness.prepare_candidate(
               connection,
               identity,
               candidate,
               [audio_input?: true, room_output?: true, speech_to_text?: true],
               options
             )

    assert provider in graph.resources
    refute speech in graph.resources
    assert {:ok, ^speech, :ready} = SpeechToText.readiness(speech.instance)
    assert Authority.snapshot(authority) == policy

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "candidate-speech",
         resources: graph.resources,
         deadline_ms: Keyword.fetch!(options, :deadline_ms)},
        id: :candidate_speech
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :preparing}}, 1_000
    refute_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}

    TestSpeechToTextTransport.deliver(
      replacement,
      ~s({"type":"Connected","request_id":"replacement-request","sequence_id":0})
    )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 1_000
    assert :ok = ConnectionReadiness.discard_candidate(graph)
    monitor = Process.monitor(replacement)
    assert :ok = SpeechToText.discard_policy(speech.instance, prepared_speech.token)
    assert_receive {:DOWN, ^monitor, :process, ^replacement, _reason}, 1_000
    assert :ok = RoomMixer.discard_policy(mixer, prepared_mixer.token)
    assert {:ok, ^speech, :ready} = SpeechToText.readiness(speech.instance)
    assert Authority.snapshot(authority) == policy
    verify_prepared_room(plan, room, speech, options)
  end

  defp verify_prepared_room(plan, room, speech, options) do
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.{Collector, Preparation}
    alias Vxpipe.Gateway.Media.RoomAudioEgress

    [{room_authority, _}] =
      Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    assert {:ok, room_binding} = CallEngine.RoomAuthority.readiness_binding(room_authority)
    authority = Authority.whereis(room.incarnation_id)
    current = Authority.snapshot(authority)

    assert {:ok, candidate} =
             Authority.preview_presence(authority, current.present_participant_ids)

    outputs =
      Enum.map(room_binding.connections, fn {_id, connection} ->
        assert {:ok, binding} = GenServer.call(connection.pid, :vxpipe_connection_readiness)
        assert :ok = RoomAudioEgress.hold(binding.room_output, 1)
        binding.room_output
      end)

    assert length(outputs) == 2
    assert {:ok, prepared} = Preparation.run_candidate(room_authority, candidate, options)
    assert map_size(prepared.connections) == 2
    assert speech in prepared.resources
    assert Enum.any?(prepared.resources, &(&1.kind == :recording_writer))
    assert Enum.any?(prepared.resources, &(&1.kind == :recording))
    assert Enum.any?(prepared.resources, &(&1.kind == :transcript_router))
    assert {:ok, ^speech, :ready} = CallEngine.Capability.SpeechToText.readiness(speech.instance)
    refute_receive {:test_stt_transport_started, _replacement, _connection}

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: room.incarnation_id,
         attempt_id: "whole-room-retained",
         resources: prepared.resources,
         deadline_ms: Keyword.fetch!(options, :deadline_ms)},
        id: :whole_room_retained
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert :ok = Preparation.discard(prepared)
    assert Authority.snapshot(authority) == current
    assert {:ok, ^speech, :ready} = CallEngine.Capability.SpeechToText.readiness(speech.instance)

    verify_recording_preparation_boundary(
      room_authority,
      room_binding,
      authority,
      current,
      plan,
      options
    )

    Enum.each(outputs, fn output -> assert :ok = RoomAudioEgress.release(output, 1) end)
  end

  defp verify_recording_preparation_boundary(
         room_authority,
         room_binding,
         authority,
         current,
         plan,
         options
       ) do
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.Preparation

    recording = room_binding.room.recording
    assert {:ok, before} = CallEngine.RoomRecording.readiness_resources(recording)
    caller = Map.fetch!(plan.participants, "caller").participant_id

    assert {:ok, candidate} =
             Authority.preview_presence(
               authority,
               MapSet.delete(current.present_participant_ids, caller)
             )

    assert {:ok, future} = Preparation.run_candidate(room_authority, candidate, options)
    assert Enum.any?(future.resources, &(&1.kind == :recording))
    assert {:ok, ^before} = CallEngine.RoomRecording.readiness_resources(recording)
    assert Authority.snapshot(authority) == current
    assert :ok = Preparation.discard(future)

    assert {:ok, retained} =
             Authority.preview_presence(authority, current.present_participant_ids)

    assert {:ok, retry} = Preparation.run_candidate(room_authority, retained, options)
    assert :ok = Preparation.discard(retry)
  end

  defp compile_plan do
    resource_id = unique_id("human-transfer-definition")

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "start_call"
                     }
                   },
                   "reception" => %{
                     type: "agent",
                     prompt: "Route callers safely.",
                     capabilities: %{
                       model_inference: "test-model",
                       text_to_speech: "test-voice"
                     },
                     tools: %{},
                     transfers: ["human-support"]
                   },
                   "human-support" => %{
                     type: "human",
                     description: "A human support specialist",
                     capabilities: %{speech_to_text: "test-stt"},
                     connection: %{
                       service: "web",
                       mode: "receive",
                       admission: "transfer"
                     },
                     transfer_notice: "This call is recorded."
                   },
                   "observer" => %{
                     type: "human",
                     connection: %{service: "web", mode: "receive", admission: "start_call"},
                     capabilities: %{},
                     while_present: %{save_transcripts: false}
                   },
                   "recording-restriction" => %{
                     type: "human",
                     connection: %{service: "web", mode: "receive", admission: "start_call"},
                     capabilities: %{},
                     while_present: %{record_audio: false}
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: resource_id,
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: unique_id("tenant-human-transfer"),
               actor_id: unique_id("actor-human-transfer"),
               call_id: unique_id("call-human-transfer"),
               room_id: unique_id("room-human-transfer")
             )

    assert {:ok, plan} =
             DefinitionCompiler.compile(definition, invocation, %{
               capability_profiles: %{
                 "test-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: "test:scripted"}
                 },
                 "test-stt" => %{
                   kind: :speech_to_text,
                   provider: Flux,
                   options: %{model: "flux-general-en", encoding: :opus, sample_rate: 48_000}
                 },
                 "test-voice" => %{
                   kind: :text_to_speech,
                   provider: FluxTextToSpeech,
                   options: %{
                     model: "flux-test-voice",
                     encoding: :linear16,
                     sample_rate: 48_000
                   }
                 }
               },
               host_tools: %{}
             })

    plan
  end

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

  defp connect(session_id, channel_label) do
    client_id = unique_id("client")
    child_spec = Supervisor.child_spec({PeerConnection, []}, id: {PeerConnection, client_id})
    client = start_supervised!(child_spec)
    :ok = PeerConnection.controlling_process(client, self())

    channel_ref = create_channel(client, channel_label)
    input_track = MediaStreamTrack.new(:audio)

    assert {:ok, _transceiver} =
             PeerConnection.add_transceiver(client, input_track, direction: :sendrecv)

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

    :ok =
      PeerConnection.set_remote_description(
        client,
        %SessionDescription{type: :answer, sdp: answer_sdp}
      )

    assert_receive {:ex_webrtc, ^client, {:ice_candidate, %ICECandidate{} = candidate}}, 5_000
    patch_candidate(connection_id, candidate)
    assert_receive {:ex_webrtc, ^client, {:connection_state_change, :connected}}, 5_000

    if channel_ref != nil do
      assert_receive {:ex_webrtc, ^client, {:data_channel_state_change, ^channel_ref, :open}},
                     5_000
    end

    assert_receive {:ex_webrtc, ^client,
                    {:track, %MediaStreamTrack{kind: :audio} = output_track}},
                   5_000

    %{
      client: client,
      channel_ref: channel_ref,
      connection_id: connection_id,
      input_track_id: input_track.id,
      output_track_id: output_track.id
    }
  end

  defp create_channel(_client, nil), do: nil

  defp create_channel(client, label) do
    assert {:ok, %DataChannel{ref: channel_ref}} =
             PeerConnection.create_data_channel(client, label, ordered: true)

    channel_ref
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

  defp send_rtvi_text(connection) do
    PeerConnection.send_data(
      connection.client,
      connection.channel_ref,
      JSON.encode!(%{
        "id" => unique_id("turn"),
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{
          "content" => "Please connect me to human support.",
          "options" => %{"run_immediately" => true, "audio_response" => false}
        }
      })
    )
  end

  defp await_sideband(connection, type, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_sideband(connection, type, deadline)
  end

  defp send_acceptance(connection, id, attempt_id) do
    PeerConnection.send_data(
      connection.client,
      connection.channel_ref,
      JSON.encode!(%{
        "id" => id,
        "type" => "transfer.accept",
        "data" => %{"attempt_id" => attempt_id}
      })
    )
  end

  defp do_await_sideband(connection, type, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    client = connection.client
    channel_ref = connection.channel_ref

    receive do
      {:ex_webrtc, ^client, {:data, ^channel_ref, payload}} ->
        message = JSON.decode!(payload)

        if message["type"] == type do
          message
        else
          do_await_sideband(connection, type, deadline)
        end
    after
      remaining -> flunk("timed out waiting for #{type}")
    end
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
    client = connection.client
    output_track_id = connection.output_track_id

    receive do
      {:ex_webrtc, ^client, {:rtp, ^output_track_id, _rid, %Packet{} = packet}} -> packet
    after
      timeout_ms -> flunk("timed out waiting for WebRTC audio")
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
