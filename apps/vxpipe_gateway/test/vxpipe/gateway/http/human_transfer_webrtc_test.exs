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

  test "AI handoff waits for destination voice readiness and cues before its greeting" do
    plan = compile_plan(agent_destination: true)
    caller = Map.fetch!(plan.participants, "caller")
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
    source_monitor = Process.monitor(source_tts)

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    client =
      plan |> issue_session(room, caller.participant_id) |> then(&connect(&1.session_id, "chat"))

    assert :ok = send_rtvi_text(client, "transfer-to-agent", true)
    assert_receive {:test_agent_runtime_stream, provider, _}, 2_000

    assert {:ok, call} =
             ToolCall.new(
               id: "agent-handoff",
               name: "transfer",
               arguments: %{"destination" => "billing"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_transport_started, destination_tts, _}, 2_000
    progress = await_transfer_progress(client, "preparing", ["text_to_speech"])
    assert progress["destination"] == "billing"

    assert Enum.sort(Map.keys(progress)) == [
             "attempt_id",
             "blockers",
             "destination",
             "elapsed_ms",
             "phase"
           ]

    refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 150
    refute_receive {:test_tts_control, ^destination_tts, _}, 50
    assert client |> await_audio(2_000) |> decodable_pcm_size() == 1_920

    assert :ok = send_rtvi_text(client, "held-during-agent-transfer")

    assert %{"id" => "held-during-agent-transfer"} =
             await_sideband(client, "error-response", 2_000)

    TestTextToSpeechTransport.deliver_control(
      destination_tts,
      ~s({"type":"Connected","request_id":"destination-ready"})
    )

    assert %{"attempt_id" => attempt} = await_transfer_progress(client, "completed")
    assert attempt == progress["attempt_id"]
    assert :ok = await_tone(client, 1_000, 3_000)
    assert_receive {:test_tts_control, ^destination_tts, speak}, 3_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Billing is ready."}
    assert_receive {:test_tts_control, ^destination_tts, _flush}, 2_000
    assert_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 2_000

    TestTextToSpeechTransport.deliver_control(
      destination_tts,
      ~s({"type":"SpeechStarted","speech_id":"billing"})
    )

    pcm =
      for sample <- 0..4_799, into: <<>> do
        amplitude = round(12_000 * :math.sin(2 * :math.pi() * 1_500 * sample / 48_000))
        <<amplitude::little-signed-16>>
      end

    reference = TestTextToSpeechTransport.deliver_audio_with_result(destination_tts, pcm)
    assert_receive {:test_tts_audio_result, ^reference, :ok}, 2_000

    TestTextToSpeechTransport.deliver_control(
      destination_tts,
      ~s({"type":"SpeechMetadata","speech_id":"billing"})
    )

    assert :ok = await_tone(client, 1_500, 2_000)
    assert :ok = send_rtvi_text(client, "talk-to-billing")

    assert_receive {:test_agent_runtime_stream, _provider,
                    %{messages: [%{content: "Handle billing requests."} | _]}},
                   2_000
  end

  for wait_mode <- [:defaults, :custom_url, :silent_caller, :silent_all] do
    @tag wait_mode: wait_mode
    test "human handoff gates and then relays conversation with #{wait_mode} waits", %{
      wait_mode: mode
    } do
      alias Vxpipe.CallEngine.MediaPolicy.Authority

      {wait_sounds, options} = wait_configuration(mode)
      plan = compile_plan(wait_sounds: wait_sounds)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")

      assert {:ok, room} =
               CallEngine.start_call(
                 plan,
                 Keyword.put(options, :recording,
                   enabled: true,
                   targets: [:individual_tracks],
                   writer: {Vxpipe.CallEngine.TestRecordingWriter, observer: self()},
                   maximum_pull_frames: 20
                 )
               )

      if mode == :custom_url,
        do:
          assert_receive(
            {:test_opening_audio_fetch, "https://media.example.com/handoff.wav", _},
            1_000
          )

      stop_room_on_exit(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
      source_monitor = Process.monitor(source_tts)

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat"))

      assert :ok = send_rtvi_text(caller_client)
      assert_receive {:test_agent_runtime_stream, source_provider, _}, 2_000

      assert {:ok, call} =
               ToolCall.new(
                 id: "ready-human-transfer",
                 name: "transfer",
                 arguments: %{
                   "destination" => "human-support",
                   "reason" => "Please connect human support."
                 }
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
      send(source_provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000

      # The caller waits from transfer authorization, before a destination even connects.
      case mode do
        mode when mode in [:silent_caller, :silent_all] -> refute_audio(caller_client, 150)
        :custom_url -> await_tone(caller_client, 250, 2_000)
        :defaults -> assert caller_client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
      end

      assert :ok = send_rtvi_text(caller_client, "before-destination")

      assert %{"type" => "error-response", "id" => "before-destination"} =
               await_sideband(caller_client, "error-response", 2_000)

      support_client =
        plan
        |> issue_session(room, support.participant_id)
        |> then(&connect(&1.session_id, "vxpipe"))

      %{"data" => %{"attempt_id" => attempt_id}} =
        await_sideband(support_client, "transfer.preparation", 5_000)

      [{room_authority, _}] =
        Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

      {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(room_authority)
      connection = Map.fetch!(binding.connections, support_client.connection_id).pid
      policy = Authority.snapshot(binding.policy_authority)
      assert_receive {:test_tts_control, ^briefing_tts, _speak}, 2_000
      assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000

      assert :ok = send_acceptance(support_client, "accept-before-briefing", attempt_id)

      assert %{"id" => "accept-before-briefing", "type" => "error"} =
               await_sideband(support_client, "error", 2_000)

      assert :sys.get_state(room_authority).pending_participant_transfer.accepted? == false

      TestTextToSpeechTransport.deliver_control(
        briefing_tts,
        ~s({"type":"SpeechStarted","request_id":"req","speech_id":"readiness-briefing"})
      )

      TestTextToSpeechTransport.deliver_audio(briefing_tts, :binary.copy(<<1, 0>>, 960))

      TestTextToSpeechTransport.deliver_control(
        briefing_tts,
        ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"readiness-briefing"})
      )

      assert support_client |> await_audio(5_000) |> decodable_pcm_size() == 1_920

      assert %{"data" => %{"attempt_id" => ^attempt_id}} =
               await_sideband(support_client, "transfer.acceptance_ready", 2_000)

      assert :ok = send_acceptance(support_client, "accept-ready-support", attempt_id)

      assert_receive {:test_stt_transport_started, joining_stt, _}, 2_000
      %{"data" => progress} = await_sideband(support_client, "transfer.progress", 2_000)
      assert progress["attempt_id"] == attempt_id
      assert progress["phase"] == "preparing"
      assert "speech_to_text" in progress["blockers"]
      assert is_integer(progress["elapsed_ms"]) and progress["elapsed_ms"] >= 0
      assert Enum.sort(Map.keys(progress)) == ["attempt_id", "blockers", "elapsed_ms", "phase"]

      case mode do
        :silent_all ->
          refute_audio(support_client, 150)

        :custom_url ->
          await_tone(support_client, 250, 2_000)

        _default_joining ->
          assert support_client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
      end

      # A private microphone must not feed either the provider or the eventual room.
      send_tone(support_client, 1_500, 1)
      refute_tone(caller_client, 1_500, 200)
      refute_receive {:test_stt_audio, ^joining_stt, _audio}, 100
      {:ok, private} = GenServer.call(connection, :vxpipe_connection_readiness)
      assert private.attachment.admission == :transfer_preparation
      assert Authority.snapshot(binding.policy_authority) == policy
      refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 100
      assert :ok = send_rtvi_text(caller_client, "held-turn")

      assert %{"type" => "error-response", "id" => "held-turn"} =
               await_sideband(caller_client, "error-response", 2_000)

      refute_receive {:test_agent_runtime_stream, _model,
                      %{correlation: %{correlation_id: "held-turn"}}},
                     100

      TestSpeechToTextTransport.deliver(
        joining_stt,
        ~s({"type":"Connected","request_id":"ready-human-stt","sequence_id":0})
      )

      for phase <- ["cue", "releasing"] do
        assert %{"data" => %{"attempt_id" => ^attempt_id, "blockers" => []}} =
                 await_sideband(support_client, "transfer.progress", 5_000, phase)
      end

      assert %{"data" => %{"attempt_id" => ^attempt_id}} =
               await_sideband(support_client, "transfer.active", 5_000)

      {:ok, admitted} = GenServer.call(connection, :vxpipe_connection_readiness)
      assert admitted.attachment.admission == :main
      assert admitted.output == private.output
      assert admitted.room_input == private.room_input
      assert admitted.room_output == private.room_output
      assert admitted.attachment.media_ingress == private.attachment.media_ingress
      refute_receive {:test_stt_transport_started, _replacement, _}, 100
      assert_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 2_000
      assert {:ok, final} = CallEngine.RoomAuthority.readiness_binding(room_authority)
      assert final.attempt == nil
      assert {:ok, _binding, :ready} = Vxpipe.Gateway.WebRTC.Connection.readiness(connection)

      # Decode the mandatory cue on both outputs, including queued pre-activation RTP.
      await_tone(caller_client, 1_000, 5_000)
      await_tone(support_client, 1_000, 5_000)
      refute_receive {:test_stt_audio, ^joining_stt, _held_or_private_audio}, 100
      refute_receive {:test_recording_chunk, _stream, _private_audio}, 100
      refute_receive {:test_opening_audio_fetch, _url, _limits}

      # Distinct tones prove conversational media traverses the bridge. A queued wait/cue
      # packet cannot satisfy either assertion, unlike checking only for decodable RTP.
      send_tone(caller_client, 500, 1)
      await_tone(support_client, 500, 5_000)
      send_tone(support_client, 1_500, 11)
      await_tone(caller_client, 1_500, 5_000)
      assert_receive {:test_stt_audio, ^joining_stt, _conversation_audio}, 2_000
      caller_id = caller.participant_id
      support_id = support.participant_id

      for participant_id <- [caller_id, support_id] do
        assert_receive {:test_recording_writer_opened, _writer, _recorder,
                        %{participant_id: ^participant_id, stream_id: stream_id}},
                       2_000

        assert_receive {:test_recording_chunk, ^stream_id, chunk}, 2_000
        assert byte_size(chunk.payload) > 0
      end

      for {event, sequence} <- [{"StartOfTurn", 1}, {"EndOfTurn", 2}] do
        TestSpeechToTextTransport.deliver(
          joining_stt,
          JSON.encode!(%{
            "type" => "TurnInfo",
            "request_id" => "ready-human-stt",
            "sequence_id" => sequence,
            "event" => event,
            "turn_index" => 0,
            "audio_window_start" => 0.0,
            "audio_window_end" => 1.0,
            "transcript" => "The support agent is connected.",
            "words" => [],
            "end_of_turn_confidence" => 0.8,
            "trigger" => "model"
          })
        )
      end

      support_id = support.participant_id

      assert %{"data" => %{"user_id" => ^support_id, "final" => false}} =
               await_sideband(caller_client, "user-transcription", 5_000)

      assert %{
               "data" => %{
                 "text" => "The support agent is connected.",
                 "user_id" => ^support_id,
                 "final" => true
               }
             } =
               await_sideband(caller_client, "user-transcription", 5_000)
    end
  end

  for preparation <- [:none, :before_policy_change, :during_readiness, :during_unrelated_change] do
    test "human handoff reconciles speech demand with #{preparation} preparation" do
      restriction = %{transcript_routes: %{}, save_transcripts: false}

      plan =
        compile_plan(
          support_policy: if(unquote(preparation) == :none, do: restriction, else: %{}),
          observer_policy:
            if(unquote(preparation) == :during_unrelated_change,
              do: %{},
              else: restriction
            )
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = CallEngine.start_call(plan)
      stop_room_on_exit(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat"))

      policy_change =
        if unquote(preparation) != :none do
          observer = Map.fetch!(plan.participants, "observer")

          assert {:ok, join} =
                   CallEngine.Command.JoinParticipant.new(
                     tenant_id: plan.tenant_id,
                     actor_id: plan.actor_id,
                     room_id: plan.room_id,
                     participant_id: observer.participant_id,
                     role: :human,
                     deadline: DateTime.add(DateTime.utc_now(), 5, :second)
                   )

          assert {:ok, _participant} = CallEngine.join_participant(join)

          _observer_client =
            plan
            |> issue_session(room, observer.participant_id)
            |> then(&connect(&1.session_id, "chat"))

          policy_authority = CallEngine.MediaPolicy.Authority.whereis(room.incarnation_id)

          assert {:ok, _policy} =
                   CallEngine.MediaPolicy.Authority.leave(
                     policy_authority,
                     observer.participant_id
                   )

          {policy_authority, observer.participant_id}
        end

      assert :ok = send_rtvi_text(caller_client)
      assert_receive {:test_agent_runtime_stream, provider, _}, 2_000

      assert {:ok, call} =
               ToolCall.new(
                 id: "no-transcription-transfer",
                 name: "transfer",
                 arguments: %{"destination" => "human-support", "reason" => "Connect support."}
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
      send(provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_tts_transport_started, briefing, _}, 2_000

      support_client =
        plan
        |> issue_session(room, support.participant_id)
        |> then(&connect(&1.session_id, "vxpipe"))

      %{"data" => %{"attempt_id" => attempt}} =
        await_sideband(support_client, "transfer.preparation", 2_000)

      prior_media =
        if unquote(preparation) == :before_policy_change do
          before = capture_private_media(plan, support_client, attempt)
          {policy_authority, observer} = policy_change

          assert {:ok, _policy} =
                   CallEngine.MediaPolicy.Authority.admit(policy_authority, observer)

          before
        end

      assert_receive {:test_tts_control, ^briefing, _speak}, 2_000
      assert_receive {:test_tts_control, ^briefing, _flush}, 2_000

      TestTextToSpeechTransport.deliver_control(
        briefing,
        ~s({"type":"SpeechStarted","request_id":"req","speech_id":"no-stt-briefing"})
      )

      TestTextToSpeechTransport.deliver_audio(briefing, :binary.copy(<<1, 0>>, 960))

      TestTextToSpeechTransport.deliver_control(
        briefing,
        ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"no-stt-briefing"})
      )

      assert %{"data" => %{"attempt_id" => ^attempt}} =
               await_sideband(support_client, "transfer.acceptance_ready", 2_000)

      assert :ok = send_acceptance(support_client, "accept-without-transcription", attempt)

      prior_media =
        if unquote(preparation) in [:during_readiness, :during_unrelated_change] do
          assert_receive {:test_stt_transport_started, transport, _}, 2_000

          assert %{"data" => %{"phase" => "preparing", "blockers" => blockers}} =
                   await_sideband(support_client, "transfer.progress", 2_000)

          assert "speech_to_text" in blockers

          before = capture_private_media(plan, support_client, attempt)
          {policy_authority, observer} = policy_change

          assert {:ok, _policy} =
                   CallEngine.MediaPolicy.Authority.admit(policy_authority, observer)

          if unquote(preparation) == :during_unrelated_change do
            TestSpeechToTextTransport.deliver(
              transport,
              ~s({"type":"Connected","request_id":"retained-after-policy-change","sequence_id":0})
            )
          end

          before
        else
          prior_media
        end

      assert %{"data" => %{"attempt_id" => ^attempt}} =
               await_sideband(support_client, "transfer.active", 2_000)

      [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
      assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)
      joining = Map.fetch!(binding.connections, support_client.connection_id).pid
      assert {:ok, media} = GenServer.call(joining, :vxpipe_connection_readiness)
      assert media.attachment.admission == :main

      if unquote(preparation) != :during_unrelated_change,
        do: assert(media.attachment.media_ingress == nil)

      assert {:ok, _resource, :ready} = Vxpipe.Gateway.WebRTC.Connection.readiness(joining)
      refute_receive {:test_stt_transport_started, _transport, _}, 100

      if prior_media do
        {before, monitors, connections} = prior_media
        assert media.instance == before.instance
        assert media.output == before.output
        assert media.room_input == before.room_input
        assert media.room_output == before.room_output

        for {actor, monitor} <- monitors do
          if unquote(preparation) == :during_unrelated_change do
            assert media.attachment.media_ingress == before.attachment.media_ingress
            refute_receive {:DOWN, ^monitor, :process, ^actor, _reason}, 100
          else
            assert_receive {:DOWN, ^monitor, :process, ^actor, :shutdown}, 1_000
          end
        end

        for {id, original} <- connections do
          connection = Map.fetch!(binding.connections, id).pid
          assert {:ok, current} = GenServer.call(connection, :vxpipe_connection_readiness)
          assert current.instance == original.instance
          assert current.output == original.output
          assert current.room_input == original.room_input
          assert current.room_output == original.room_output
        end

        send_tone(caller_client, 500, 1)
        await_tone(support_client, 500, 2_000)
        send_tone(support_client, 1_500, 1)
        await_tone(caller_client, 1_500, 2_000)
      end
    end
  end

  for loss <- [:destination, :phase, :wait_player, :agent_destination] do
    test "recovers the held caller after #{loss} loss without replacing source media" do
      agent_destination? = unquote(loss) == :agent_destination
      plan = compile_plan(agent_destination: agent_destination?)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = CallEngine.start_call(plan)
      stop_room_on_exit(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat"))

      [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
      {:ok, initial} = CallEngine.RoomAuthority.readiness_binding(authority)
      caller_connection = Map.fetch!(initial.connections, caller_client.connection_id).pid
      caller_monitor = Process.monitor(caller_connection)
      {:ok, before} = GenServer.call(caller_connection, :vxpipe_connection_readiness)
      assert :ok = send_rtvi_text(caller_client, "recover-with-speech", true)
      assert_receive {:test_agent_runtime_stream, source_provider, _}, 2_000

      assert {:ok, call} =
               ToolCall.new(
                 id: "recover-human-transfer",
                 name: "transfer",
                 arguments:
                   if(agent_destination?,
                     do: %{"destination" => "billing"},
                     else: %{"destination" => "human-support", "reason" => "Connect support."}
                   )
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
      send(source_provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_tts_transport_started, destination_tts, _}, 2_000
      assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _}, 2_000
      assert {:ok, acknowledgement} = ModelResponse.new(text: "I am connecting support.")
      send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, acknowledgement}})
      assert caller_client |> await_audio(2_000) |> decodable_pcm_size() == 1_920

      observer = self()

      release = fn ->
        send(observer, :destination_admission_released)
        :ok
      end

      support_client =
        unless agent_destination? do
          client =
            plan
            |> issue_session(room, support.participant_id, release)
            |> then(&connect(&1.session_id, "vxpipe"))

          assert %{"type" => "transfer.preparation"} =
                   await_sideband(client, "transfer.preparation", 2_000)

          client
        end

      {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)
      pending = :sys.get_state(authority).pending_participant_transfer

      case unquote(loss) do
        :agent_destination ->
          TestTextToSpeechTransport.disconnect(destination_tts, :test_destination_failed)

        :destination ->
          GenServer.stop(
            Map.fetch!(binding.connections, support_client.connection_id).pid,
            :normal
          )

        :phase ->
          Process.exit(pending.task.pid, :kill)

        :wait_player ->
          {:ok, phase} =
            CallEngine.RoomAuthority.ParticipantTransfer.Phase.scope(pending.task.pid)

          [player] = phase.audience.waits
          Process.exit(player, :kill)
      end

      unless agent_destination?, do: assert_receive(:destination_admission_released, 2_000)
      await_recovered(authority, System.monotonic_time(:millisecond) + 2_000)
      assert %{"phase" => "recovered"} = await_transfer_progress(caller_client, "recovered")
      assert :ok = await_tone(caller_client, 1_000, 2_000)
      refute_receive {:DOWN, ^caller_monitor, :process, ^caller_connection, _}, 50
      {:ok, after_recovery} = GenServer.call(caller_connection, :vxpipe_connection_readiness)
      assert after_recovery.output == before.output
      assert after_recovery.room_input == before.room_input
      assert after_recovery.room_output == before.room_output
      assert :sys.get_state(caller_connection).handoff_gate == nil
      refute_receive {:test_tts_transport_started, _replacement, _}, 50

      # Finish the scripted response to the failed tool before starting another caller turn.
      assert_receive {:test_agent_runtime_stream, recovery_provider, _}, 2_000
      assert {:ok, recovery_response} = ModelResponse.new(text: "I am still here.")
      send(recovery_provider, {:test_agent_runtime_response, {:ok, recovery_response}})

      assert %{"data" => %{"text" => "I am still here."}} =
               await_sideband(caller_client, "bot-output", 2_000)

      assert_receive {:test_tts_control, ^source_tts, speak}, 2_000
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "I am still here."}
      assert_receive {:test_tts_control, ^source_tts, _flush}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"SpeechStarted","speech_id":"recovered-speech"})
      )

      pcm =
        for sample <- 0..4_799, into: <<>> do
          amplitude = round(12_000 * :math.sin(2 * :math.pi() * 1_500 * sample / 48_000))
          <<amplitude::little-signed-16>>
        end

      reference = TestTextToSpeechTransport.deliver_audio_with_result(source_tts, pcm)
      assert_receive {:test_tts_audio_result, ^reference, :ok}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"SpeechMetadata","speech_id":"recovered-speech"})
      )

      assert :ok = await_tone(caller_client, 1_500, 2_000)

      assert %{"type" => "bot-stopped-speaking"} =
               await_sideband(caller_client, "bot-stopped-speaking", 2_000)

      assert :ok = send_rtvi_text(caller_client, "after-recovery")

      assert_receive {:test_agent_runtime_stream, retry_provider,
                      %{correlation: %{correlation_id: "after-recovery"}}},
                     2_000

      if unquote(loss) == :destination do
        assert {:ok, retry_call} =
                 ToolCall.new(
                   id: "retry-human-transfer",
                   name: "transfer",
                   arguments: %{
                     "destination" => "human-support",
                     "reason" => "Try support again."
                   }
                 )

        assert {:ok, retry_response} = ModelResponse.new(text: "", tool_calls: [retry_call])
        send(retry_provider, {:test_agent_runtime_response, {:ok, retry_response}})
        assert_receive {:test_tts_transport_started, retry_briefing, _}, 2_000

        retry_client =
          plan
          |> issue_session(room, support.participant_id, release)
          |> then(&connect(&1.session_id, "vxpipe"))

        assert %{"data" => %{"attempt_id" => attempt_id}} =
                 await_sideband(retry_client, "transfer.preparation", 2_000)

        assert_receive {:test_tts_control, ^retry_briefing, _speak}, 2_000
        assert_receive {:test_tts_control, ^retry_briefing, _flush}, 2_000

        TestTextToSpeechTransport.deliver_control(
          retry_briefing,
          ~s({"type":"SpeechStarted","speech_id":"retry-briefing"})
        )

        reference = TestTextToSpeechTransport.deliver_audio_with_result(retry_briefing, pcm)
        assert_receive {:test_tts_audio_result, ^reference, :ok}, 2_000

        TestTextToSpeechTransport.deliver_control(
          retry_briefing,
          ~s({"type":"SpeechMetadata","speech_id":"retry-briefing"})
        )

        assert :ok = await_tone(retry_client, 1_500, 2_000)

        assert %{"data" => %{"attempt_id" => ^attempt_id}} =
                 await_sideband(retry_client, "transfer.acceptance_ready", 2_000)

        assert :ok = send_acceptance(retry_client, "accept-retry", attempt_id)
        assert_receive {:test_stt_transport_started, retry_stt, _}, 2_000

        TestSpeechToTextTransport.deliver(
          retry_stt,
          ~s({"type":"Connected","request_id":"retry-stt","sequence_id":0})
        )

        assert %{"data" => %{"attempt_id" => ^attempt_id}} =
                 await_sideband(retry_client, "transfer.active", 5_000)

        refute_receive {:DOWN, ^caller_monitor, :process, ^caller_connection, _}, 50
        send_tone(retry_client, 1_500, 1)
        assert :ok = await_tone(caller_client, 1_500, 2_000)
      end
    end
  end

  for failure <- [:phase, :room_input, :room_output] do
    @private_media_failure failure
    test "private WebRTC media stays gated and cleans up after #{@private_media_failure} loss" do
      alias Vxpipe.CallEngine.MediaPolicy.Authority
      alias Vxpipe.Gateway.WebRTC.Connection

      plan = compile_plan(wait_sounds: nil)
      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = CallEngine.start_call(plan)
      stop_room_on_exit(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller_client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat"))

      assert :ok = send_rtvi_text(caller_client)
      assert_receive {:test_agent_runtime_stream, source_provider, _}, 2_000

      assert {:ok, call} =
               ToolCall.new(
                 id: "private-media-transfer",
                 name: "transfer",
                 arguments: %{"destination" => "human-support", "reason" => "A private handoff."}
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
      send(source_provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_tts_transport_started, _briefing_tts, _}, 2_000

      support_client =
        plan
        |> issue_session(room, support.participant_id)
        |> then(&connect(&1.session_id, "vxpipe"))

      %{"data" => %{"attempt_id" => attempt_id}} =
        await_sideband(support_client, "transfer.preparation", 5_000)

      [{room_authority, _}] =
        Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

      {:ok, room_binding} = CallEngine.RoomAuthority.readiness_binding(room_authority)
      connection = Map.fetch!(room_binding.connections, support_client.connection_id).pid
      {:ok, before} = GenServer.call(connection, :vxpipe_connection_readiness)
      phase = :sys.get_state(room_authority).pending_participant_transfer

      assert {:error, _} =
               Connection.prepare_transfer_media(support_client.connection_id, "stale")

      assert {:ok, private} =
               Connection.prepare_transfer_media(support_client.connection_id, attempt_id)

      assert private.owner == phase.task.pid
      assert private.attempt_id == phase.attempt_id
      assert private.deadline_ms == phase.deadline_ms

      assert {:ok, ^private} =
               Connection.prepare_transfer_media(support_client.connection_id, attempt_id)

      {:ok, binding} = GenServer.call(connection, :vxpipe_connection_readiness)
      assert binding.output == before.output
      assert binding.attachment.admission == :transfer_preparation
      assert binding.attachment.room_audio_input_mode == :disabled
      assert binding.attachment.room_audio_output_mode == :disabled
      assert is_pid(binding.room_input)
      assert is_pid(binding.room_output)
      assert is_pid(binding.attachment.media_ingress)
      assert Keyword.fetch!(binding.policy_subscription, :subscriber) == binding.room_output
      assert Keyword.fetch!(binding.policy_subscription, :mode) == :mix_minus

      policy = Authority.snapshot(Authority.whereis(room.incarnation_id))
      input = :sys.get_state(binding.room_input)
      output = :sys.get_state(binding.room_output)
      assert input.policy == policy
      assert output.policy == policy
      assert input.pipeline_pid == nil
      assert output.pipeline_pid == nil
      assert output.subscription == nil
      refute MapSet.member?(policy.present_participant_ids, support.participant_id)
      refute_receive {:test_stt_transport_started, _, _}

      assert :ok = send_audio(support_client, 1, 960, -8_000)
      refute_audio(caller_client, 200)

      observer = Map.fetch!(plan.participants, "observer").participant_id
      authority = Authority.whereis(room.incarnation_id)
      assert {:ok, _restricted} = Authority.admit(authority, observer)

      assert {:ok, ^private} =
               Connection.prepare_transfer_media(support_client.connection_id, attempt_id)

      assert {:ok, policy} = Authority.leave(authority, observer)

      assert {:ok, ^private} =
               Connection.prepare_transfer_media(support_client.connection_id, attempt_id)

      for actor <- private.enforcers do
        assert :sys.get_state(actor).policy == policy
      end

      refute_receive {:test_stt_transport_started, _, _}

      verify_private_candidate(
        plan,
        room,
        room_authority,
        caller_client,
        binding,
        private,
        policy
      )

      monitors = Enum.map(private.enforcers, &{&1, Process.monitor(&1)})
      connection_monitor = Process.monitor(connection)

      target =
        case @private_media_failure do
          :phase -> phase.task.pid
          kind -> Map.fetch!(binding, kind)
        end

      Process.exit(target, :kill)
      assert_receive {:DOWN, ^connection_monitor, :process, ^connection, reason}, 2_000
      assert reason == :shutdown

      for {actor, monitor} <- monitors do
        assert_receive {:DOWN, ^monitor, :process, ^actor, _reason}, 2_000
      end

      await_recovered(room_authority, System.monotonic_time(:millisecond) + 2_000)
      assert Authority.snapshot(Authority.whereis(room.incarnation_id)) == policy
      assert {:ok, _resource, :ready} = Connection.readiness(caller_client.connection_id)
    end
  end

  defp verify_private_candidate(plan, room, room_authority, caller, joining, private, policy) do
    alias Vxpipe.CallEngine.Media.OutputSink
    alias Vxpipe.CallEngine.MediaPolicy.Authority
    alias Vxpipe.CallEngine.Readiness.{Collector, Preparation}
    alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase

    {:ok, room_binding} = CallEngine.RoomAuthority.readiness_binding(room_authority)
    caller_connection = Map.fetch!(room_binding.connections, caller.connection_id).pid
    {:ok, caller_binding} = GenServer.call(caller_connection, :vxpipe_connection_readiness)
    source = Map.fetch!(plan.participants, "reception").participant_id
    source_capabilities = Map.fetch!(room_binding.participants, source)
    caller_input = :sys.get_state(caller_binding.room_input).pipeline_pid
    caller_output = :sys.get_state(caller_binding.room_output).pipeline_pid

    presence =
      policy.present_participant_ids
      |> MapSet.delete(source)
      |> MapSet.put(joining.identity.participant_id)

    assert {:ok, candidate} = Authority.preview_presence(room_binding.policy_authority, presence)
    assert {:ok, phase} = Phase.scope(private.owner)
    generation = phase.audience.scope.generation
    assert :ok = OutputSink.hold(joining.output, generation)

    options = [
      owner: private.owner,
      attempt_id: private.attempt_id,
      deadline_ms: private.deadline_ms,
      generation: generation
    ]

    assert {:ok, prepared} = Preparation.run_candidate(room_authority, candidate, options)

    assert MapSet.new(Map.keys(prepared.connections)) ==
             MapSet.new([caller.connection_id, joining.identity.connection_id])

    refute Enum.any?(prepared.resources, &(&1.scope == {:participant, source}))
    assert Enum.any?(prepared.resources, &(&1.kind == :speech_to_text))

    assert Enum.any?(
             prepared.resources,
             &(&1.kind == :room_audio_ingress and
                 &1.scope == {:participant, joining.identity.participant_id})
           )

    assert Enum.any?(
             prepared.resources,
             &(&1.kind == :room_audio_egress and
                 &1.scope == {:participant, joining.identity.participant_id})
           )

    assert_receive {:test_stt_transport_started, private_stt, _}, 2_000

    collector =
      start_supervised!(
        {Collector,
         Keyword.merge(options,
           owner: self(),
           incarnation_id: room.incarnation_id,
           resources: prepared.resources
         )}
      )

    assert Collector.snapshot(collector).status == :preparing
    refute_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 100

    TestSpeechToTextTransport.deliver(
      private_stt,
      ~s({"type":"Connected","request_id":"private-ready","sequence_id":0})
    )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 2_000
    assert Authority.snapshot(room_binding.policy_authority) == policy
    assert :sys.get_state(joining.room_input).pipeline_pid == nil
    assert :sys.get_state(joining.room_output).pipeline_pid == nil
    assert :sys.get_state(caller_binding.room_input).pipeline_pid == caller_input
    assert :sys.get_state(caller_binding.room_output).pipeline_pid == caller_output
    {:ok, retained} = CallEngine.RoomAuthority.readiness_binding(room_authority)
    assert Map.fetch!(retained.participants, source) == source_capabilities

    # Keep the prepared graph owned by the phase until the test injects its target loss.
    # Discarding it here can trigger recovery before that failure is exercised.
    stop_supervised!({Collector, private.attempt_id})
  end

  test "a destination accepts privately before joining bidirectional room audio" do
    plan = compile_plan(wait_sounds: nil)

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

    assert %{"data" => %{"attempt_id" => ^attempt_id}} =
             await_sideband(support_client, "transfer.acceptance_ready", 2_000)

    :ok = send_acceptance(support_client, "accept-support", attempt_id)
    assert_receive {:test_stt_transport_started, support_stt, _connection}, 2_000

    TestSpeechToTextTransport.deliver(
      support_stt,
      ~s({"type":"Connected","request_id":"support-request","sequence_id":0})
    )

    assert %{
             "id" => ^attempt_id,
             "type" => "transfer.active",
             "data" => %{"attempt_id" => ^attempt_id}
           } = await_sideband(support_client, "transfer.active", 5_000)

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

    generation = System.unique_integer([:positive, :monotonic])
    assert :ok = RoomAudioEgress.hold(binding.room_output, generation)

    options = [
      owner: self(),
      attempt_id: "candidate-speech",
      generation: generation,
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

        assert :ok =
                 RoomAudioEgress.hold(binding.room_output, Keyword.fetch!(options, :generation))

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

    Enum.each(outputs, fn output ->
      assert :ok = RoomAudioEgress.release(output, Keyword.fetch!(options, :generation))
    end)
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

  defp capture_private_media(plan, client, attempt) do
    assert {:ok, private} =
             Vxpipe.Gateway.WebRTC.Connection.prepare_transfer_media(
               client.connection_id,
               attempt
             )

    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)

    connections =
      Map.new(binding.connections, fn {id, connection} ->
        assert {:ok, media} = GenServer.call(connection.pid, :vxpipe_connection_readiness)
        {id, media}
      end)

    media = Map.fetch!(connections, client.connection_id)
    speech = Enum.reject(private.enforcers, &(&1 in [media.room_input, media.room_output]))
    assert length(speech) == 2
    {media, Enum.map(speech, &{&1, Process.monitor(&1)}), connections}
  end

  defp wait_configuration(:defaults), do: {%{}, []}
  defp wait_configuration(:silent_caller), do: {%{transfer_to_human: nil}, []}
  defp wait_configuration(:silent_all), do: {nil, []}

  defp wait_configuration(:custom_url) do
    cache =
      start_supervised!(
        {CallEngine.OpeningAudio.AssetCache, maximum_entries: 8, maximum_bytes: 8_388_608}
      )

    pcm =
      for sample <- 0..9_599, into: <<>> do
        amplitude = round(12_000 * :math.sin(2 * :math.pi() * 250 * sample / 48_000))
        <<amplitude::little-signed-16>>
      end

    format =
      <<1::little-16, 1::little-16, 48_000::little-32, 96_000::little-32, 2::little-16,
        16::little-16>>

    body = "fmt " <> <<16::little-32>> <> format <> "data" <> <<byte_size(pcm)::little-32>> <> pcm
    wave = "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
    url = "https://media.example.com/handoff.wav"

    {%{transfer_to_human: url, transfer_joining: url},
     [
       wait_sound_settings: [
         cache: cache,
         fetcher:
           {CallEngine.TestOpeningAudioFetcher,
            [
              observer: self(),
              response:
                {:ok, %CallEngine.OpeningAudio.Download{body: wave, content_type: "audio/wav"}}
            ]}
       ]
     ]}
  end

  defp compile_plan(options \\ []) do
    resource_id = unique_id("human-transfer-definition")

    assert {:ok, definition} =
             CallDefinition.new(
               %{
                 schema_version: CallDefinition.schema_version(),
                 entry_caller: "caller",
                 entry_receiver: "reception",
                 defaults: %{capabilities: %{}},
                 wait_sounds: Keyword.get(options, :wait_sounds, %{}),
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
                     transfers:
                       if(Keyword.get(options, :agent_destination),
                         do: ["billing"],
                         else: ["human-support"]
                       )
                   },
                   "billing" => %{
                     type: "agent",
                     prompt: "Handle billing requests.",
                     capabilities: %{model_inference: "test-model", text_to_speech: "test-voice"},
                     first_message: %{mode: "fixed", text: "Billing is ready."}
                   },
                   "human-support" => %{
                     type: "human",
                     description: "A human support specialist",
                     while_present: Keyword.get(options, :support_policy, %{}),
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
                     while_present:
                       Keyword.get(options, :observer_policy, %{save_transcripts: false})
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

  defp issue_session(plan, room, participant_id, release \\ nil) do
    binding = [
      tenant_id: plan.tenant_id,
      actor_id: plan.actor_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant_id,
      tool_visibility: plan.tool_visibility,
      release_admission: release
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

  defp send_rtvi_text(connection, id \\ unique_id("turn"), audio_response \\ false) do
    PeerConnection.send_data(
      connection.client,
      connection.channel_ref,
      JSON.encode!(%{
        "id" => id,
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{
          "content" => "Please connect me to human support.",
          "options" => %{"run_immediately" => true, "audio_response" => audio_response}
        }
      })
    )
  end

  defp await_sideband(connection, type, timeout_ms, phase \\ nil) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_await_sideband(connection, type, deadline, phase)
  end

  defp await_transfer_progress(connection, phase, blockers \\ nil) do
    await_transfer_progress(
      connection,
      phase,
      blockers,
      System.monotonic_time(:millisecond) + 2_000
    )
  end

  defp await_transfer_progress(connection, phase, blockers, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    message = await_sideband(connection, "server-message", remaining)

    case message do
      %{
        "data" => %{
          "t" => "vxpipe.transfer",
          "v" => 1,
          "d" => %{"phase" => ^phase, "blockers" => actual} = data
        }
      }
      when is_nil(blockers) or actual == blockers ->
        data

      _other ->
        await_transfer_progress(connection, phase, blockers, deadline)
    end
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

  defp do_await_sideband(connection, type, deadline, phase) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    client = connection.client
    channel_ref = connection.channel_ref

    receive do
      {:ex_webrtc, ^client, {:data, ^channel_ref, payload}} ->
        message = JSON.decode!(payload)

        if message["type"] == type and (is_nil(phase) or message["data"]["phase"] == phase) do
          message
        else
          do_await_sideband(connection, type, deadline, phase)
        end
    after
      remaining -> flunk("timed out waiting for #{type} #{phase}")
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

  defp send_tone(connection, frequency, first_sequence) do
    encoder =
      Encoder.Native.create(48_000, 1, @application_voip, @automatic_bitrate, @signal_voice)

    started_at = System.monotonic_time(:millisecond) * 48

    for frame <- 0..9 do
      pcm =
        for sample <- 0..959, into: <<>> do
          amplitude =
            round(
              12_000 * :math.sin(2 * :math.pi() * frequency * (frame * 960 + sample) / 48_000)
            )

          <<amplitude::little-signed-16>>
        end

      assert {:ok, payload} = Encoder.Native.encode_packet(encoder, pcm, 960)

      packet =
        Packet.new(payload,
          payload_type: 111,
          sequence_number: first_sequence + frame,
          timestamp: Integer.mod(started_at + frame * 960, 4_294_967_296),
          ssrc: 123
        )

      assert :ok = PeerConnection.send_rtp(connection.client, connection.input_track_id, packet)
    end
  end

  defp await_tone(connection, frequency, timeout_ms) do
    decoder = Decoder.Native.create(48_000, 1)
    receive_tone(connection, decoder, frequency, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp receive_tone(connection, decoder, frequency, deadline) do
    packet = await_audio(connection, max(deadline - System.monotonic_time(:millisecond), 0))
    pcm = Decoder.Native.decode_packet(decoder, packet.payload)

    if tone?(pcm, frequency) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "missing #{frequency} Hz conversational audio"

      receive_tone(connection, decoder, frequency, deadline)
    end
  end

  defp refute_tone(connection, frequency, timeout_ms) do
    refute_tone(
      connection,
      Decoder.Native.create(48_000, 1),
      frequency,
      System.monotonic_time(:millisecond) + timeout_ms
    )
  end

  defp refute_tone(connection, decoder, frequency, deadline) do
    client = connection.client
    track = connection.output_track_id
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    if remaining > 0 do
      receive do
        {:ex_webrtc, ^client, {:rtp, ^track, _rid, %Packet{} = packet}} ->
          refute tone?(Decoder.Native.decode_packet(decoder, packet.payload), frequency),
                 "private microphone audio reached the held caller"

          refute_tone(connection, decoder, frequency, deadline)
      after
        remaining -> :ok
      end
    end
  end

  defp tone?(pcm, frequency) do
    samples = for <<sample::little-signed-16 <- pcm>>, do: sample

    {sine, cosine, energy} =
      samples
      |> Enum.with_index()
      |> Enum.reduce({0.0, 0.0, 0}, fn {sample, index}, {sine, cosine, energy} ->
        angle = 2 * :math.pi() * frequency * index / 48_000

        {sine + sample * :math.sin(angle), cosine + sample * :math.cos(angle),
         energy + sample * sample}
      end)

    energy > length(samples) * 1_000_000 and
      2 * (sine * sine + cosine * cosine) > 0.7 * length(samples) * energy
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

  defp await_recovered(authority, deadline) do
    state = :sys.get_state(authority)

    if state.pending_participant_transfer == nil and MapSet.size(state.held_participant_ids) == 0 do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "caller recovery did not finish"

      receive do
      after
        10 -> await_recovered(authority, deadline)
      end
    end
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
