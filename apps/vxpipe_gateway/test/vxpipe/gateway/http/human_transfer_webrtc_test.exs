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
  alias Vxpipe.CallEngine.Provider.{MorseCodeSTT, MorseCodeTTS}
  alias Vxpipe.CallEngine.Provider.MorseCode.Decoder, as: MorseDecoder
  alias Vxpipe.CallEngine.Provider.MorseCode.Encoder, as: MorseEncoder
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.SessionSupervisor

  @moduletag capture_log: true

  @application_voip 2_048
  @automatic_bitrate -1_000
  @endpoint_options Endpoint.init(cors: [])
  @signal_voice 3_001
  @morse_options [
    sample_rate: 48_000,
    unit_duration_ms: 60,
    window_duration_ms: 20,
    detection_threshold: 2_400,
    frequency_tolerance_hz: 250
  ]

  setup context do
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

    if context[:morse] do
      configured = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

      Application.put_env(
        :vxpipe_call_engine,
        Vxpipe.CallEngine.Application,
        configured
        |> Keyword.put(:speech_to_text,
          enabled: false,
          providers: %{
            MorseCodeSTT => [
              enabled: true,
              provider_options: [],
              transport: {MorseCodeSTT.Transport, []},
              media_ingress: Keyword.fetch!(speech_to_text, :media_ingress)
            ]
          }
        )
        |> Keyword.put(:text_to_speech,
          enabled: false,
          providers: %{
            MorseCodeTTS => [
              enabled: true,
              provider_options: [],
              transport: {MorseCodeTTS.Transport, [emit_interval_ms: 0]},
              maximum_requests: 2
            ]
          }
        )
      )
    end

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  @tag morse: true
  test "native peers exchange Morse speech and transcripts before and after human transfer" do
    plan = compile_plan(morse: true, transfer_notice: "E")
    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)

    caller_client =
      plan |> issue_session(room, caller.participant_id) |> then(&connect(&1.session_id, "chat"))

    caller_client = Map.put(caller_client, :morse_opus, Decoder.Native.create(48_000, 1))

    assert :ok =
             PeerConnection.send_data(
               caller_client.client,
               caller_client.channel_ref,
               JSON.encode!(%{
                 id: "morse-ready",
                 label: "rtvi-ai",
                 type: "client-ready",
                 data: %{version: "2.1.0"}
               })
             )

    await_sideband(caller_client, "bot-ready", 2_000)
    caller_client = send_morse(caller_client, "SOS")
    assert_receive {:test_agent_runtime_stream, source_provider, _}, 2_000
    assert_transcript(caller_client, caller.participant_id, "SOS")
    assert {:ok, response} = ModelResponse.new(text: "OK")
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_morse(caller_client, "OK")

    [{caller_connection, _}] =
      Registry.lookup(
        Vxpipe.Gateway.WebRTC.Registry,
        {:connection, caller_client.connection_id}
      )

    speech_input = :sys.get_state(caller_connection).speech_input
    assert %{codec: :linear16, sample_rate: 16_000, channels: 1} = speech_input.output

    caller_client = send_morse(caller_client, "ET")
    assert_transcript(caller_client, caller.participant_id, "ET")
    assert_receive {:test_agent_runtime_stream, source_provider, _}, 2_000

    assert {:ok, transfer} =
             ToolCall.new(
               id: "morse-handoff",
               name: "transfer",
               arguments: %{"destination" => "human-support", "reason" => "E"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [transfer])
    send(source_provider, {:test_agent_runtime_response, {:ok, response}})
    await_transfer_progress(caller_client, "preparing")

    support_client =
      plan
      |> issue_session(room, support.participant_id)
      |> then(&connect(&1.session_id, "vxpipe"))

    support_client = Map.put(support_client, :morse_opus, Decoder.Native.create(48_000, 1))

    %{"data" => %{"attempt_id" => attempt}} =
      await_sideband(support_client, "transfer.acceptance_ready", 5_000)

    assert_morse(support_client, "E E")
    assert :ok = send_acceptance(support_client, "morse-accept", attempt)
    await_sideband(support_client, "transfer.active", 5_000)
    await_transfer_progress(caller_client, "completed")
    assert :sys.get_state(caller_connection).speech_input == speech_input
    await_tone(caller_client, 1_000, 2_000)
    await_tone(support_client, 1_000, 2_000)
    drain_audio(caller_client)
    drain_audio(support_client)

    support_client = send_morse(support_client, "SOS")
    assert_transcript(caller_client, support.participant_id, "SOS")
    assert :ok = await_tone(caller_client, 700, 2_000)

    caller_client = send_morse(caller_client, "ET")
    assert_transcript(caller_client, caller.participant_id, "ET")
    assert :ok = await_tone(support_client, 700, 2_000)
  end

  @tag changing_listeners: true
  test "five-participant handoff retains wait cursors through monitor addition and reconnection" do
    {wait_sounds, options} = custom_wait_configuration(480_000)

    plan =
      compile_plan(
        wait_sounds: wait_sounds,
        observer_policy: %{},
        restriction_policy: %{},
        extra_participants: %{
          "monitor" => %{
            type: "human",
            connection: %{service: "web", mode: "receive", admission: "start_call"},
            capabilities: %{}
          },
          "late-monitor" => %{
            type: "human",
            connection: %{service: "web", mode: "receive", admission: "start_call"},
            capabilities: %{}
          }
        }
      )

    caller = Map.fetch!(plan.participants, "caller")
    support = Map.fetch!(plan.participants, "human-support")
    observer = Map.fetch!(plan.participants, "observer")
    assert {:ok, room} = CallEngine.start_call(plan, options)
    stop_room_on_exit(plan)
    assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
    source_monitor = Process.monitor(source_tts)

    TestTextToSpeechTransport.deliver_control(
      source_tts,
      ~s({"type":"Connected","request_id":"source-ready"})
    )

    caller_client =
      plan |> issue_session(room, caller.participant_id) |> then(&connect(&1.session_id, "chat"))

    observer_client = join_native_listener(plan, room, "observer", :monitor)
    third_client = join_native_listener(plan, room, "recording-restriction", :human)
    monitor_client = join_native_listener(plan, room, "monitor", :monitor)
    audience = [caller_client, observer_client, third_client, monitor_client]
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    assert MapSet.size(:sys.get_state(authority).participant_ids) == 5
    assert {:ok, before} = CallEngine.RoomAuthority.readiness_binding(authority)

    assert :ok = send_rtvi_text(third_client, "transfer-from-another-human", true)
    assert_receive {:test_agent_runtime_stream, provider, _}, 2_000

    assert {:ok, call} =
             ToolCall.new(
               id: "multiple-listener-handoff",
               name: "transfer",
               arguments: %{"destination" => "human-support", "reason" => "Connect support."}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:test_tts_transport_started, briefing_tts, _}, 2_000
    for peer <- audience, do: await_tone(peer, 250, 2_000)
    original_players = wait_players(room.incarnation_id)
    assert map_size(original_players) == 4
    {caller_player, _} = Map.fetch!(original_players, caller.participant_id)
    {observer_player, _} = Map.fetch!(original_players, observer.participant_id)
    pause_wait_at(caller_player, 350)
    pause_wait_at(observer_player, 150)

    late = Map.fetch!(plan.participants, "late-monitor")
    late_client = join_native_listener(plan, room, "late-monitor", :monitor)
    await_tone(late_client, 250, 2_000)
    {late_player, _} = Map.fetch!(wait_players(room.incarnation_id), late.participant_id)
    pause_wait_at(late_player, 100)
    assert await_paused_cursor(late_player, 3_000) == 192_000
    late_player_monitor = Process.monitor(late_player)

    [{late_connection, _}] =
      Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, late_client.connection_id})

    late_connection_monitor = Process.monitor(late_connection)

    participant_supervisor =
      Map.fetch!(:sys.get_state(authority).participant_supervisors, late.participant_id)

    assert :ok =
             CallEngine.RoomParticipantSupervisor.stop_participant(
               room.incarnation_id,
               participant_supervisor
             )

    assert_receive {:DOWN, ^late_connection_monitor, :process, ^late_connection, _}, 2_000
    assert_receive {:DOWN, ^late_player_monitor, :process, ^late_player, _}, 2_000

    for {participant, {player, _}} <- original_players do
      assert {^player, _} = Map.fetch!(wait_players(room.incarnation_id), participant)
    end

    late_client = join_native_listener(plan, room, "late-monitor", :monitor)
    await_tone(late_client, 250, 2_000)
    {reentered_player, _} = Map.fetch!(wait_players(room.incarnation_id), late.participant_id)
    refute reentered_player == late_player
    pause_wait_at(reentered_player, 25)
    assert await_paused_cursor(reentered_player, 2_000) == 48_000
    CallEngine.WaitSounds.Player.resume(reentered_player)
    audience = audience ++ [late_client]

    support_client =
      plan
      |> issue_session(room, support.participant_id)
      |> then(&connect(&1.session_id, "vxpipe"))

    %{"data" => %{"attempt_id" => attempt}} =
      await_sideband(support_client, "transfer.preparation", 2_000)

    assert_receive {:test_tts_control, ^briefing_tts, _speak}, 2_000
    assert_receive {:test_tts_control, ^briefing_tts, _flush}, 2_000
    deliver_voice_tone(briefing_tts, "multiple-listener-briefing", 2_000)
    await_sideband(support_client, "transfer.acceptance_ready", 2_000)
    assert :ok = send_acceptance(support_client, "accept-multiple-listeners", attempt)
    assert_receive {:test_stt_transport_started, support_stt, _}, 2_000
    await_transfer_progress(third_client, "preparing", ["speech_to_text"])
    assert {:ok, pending} = CallEngine.RoomAuthority.readiness_binding(authority)
    assert await_paused_cursor(observer_player, 8_000) == 288_000
    assert await_paused_cursor(caller_player, 8_000) == 672_000

    phase = :sys.get_state(authority).pending_participant_transfer.task.pid

    assert {:ok, %{worker: %Task{pid: worker}}} =
             CallEngine.RoomAuthority.ParticipantTransfer.Phase.scope(phase)

    assert :erlang.suspend_process(worker)

    second_sink =
      try do
        peer =
          plan
          |> issue_session(room, observer.participant_id)
          |> then(&connect(&1.session_id, "chat", false, :recvonly))

        [{connection, _}] =
          Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, peer.connection_id})

        gate = Map.get(:sys.get_state(connection), :handoff_gate)
        assert match?(%{held?: true}, gate)
        assert {:ok, media} = GenServer.call(connection, :vxpipe_connection_readiness)
        assert :ok = Vxpipe.Gateway.Media.OutputArbiter.confirm_hold(media.output, 1)
        peer
      after
        :erlang.resume_process(worker)
      end

    assert :sys.get_state(observer_player).offset == 288_000
    assert :sys.get_state(caller_player).offset == 672_000
    CallEngine.WaitSounds.Player.resume(observer_player)
    CallEngine.WaitSounds.Player.resume(caller_player)
    await_tone(second_sink, 250, 2_000)
    players = wait_players(room.incarnation_id)
    assert map_size(players) == 6

    assert {:error, :unavailable} =
             Vxpipe.Gateway.WebRTC.Connection.input_track(second_sink.connection_id)

    {observer_player, _state} = Map.fetch!(original_players, observer.participant_id)
    {current_player, observer_wait} = Map.fetch!(players, observer.participant_id)
    assert current_player == observer_player

    assert Map.keys(observer_wait.sinks) |> Enum.sort() ==
             Enum.sort([observer_client.connection_id, second_sink.connection_id])

    for {participant, {player, old}} <- original_players do
      {current_player, current} = Map.fetch!(players, participant)
      assert current_player == player
      assert current.offset >= old.offset
      assert current.asset == old.asset
    end

    [{old_connection, _}] =
      Registry.lookup(
        Vxpipe.Gateway.WebRTC.Registry,
        {:connection, observer_client.connection_id}
      )

    old_monitor = Process.monitor(old_connection)
    player_monitor = Process.monitor(observer_player)

    assert :ok =
             PeerConnection.close_data_channel(
               observer_client.client,
               observer_client.channel_ref
             )

    assert_receive {:DOWN, ^old_monitor, :process, ^old_connection, _}, 2_000
    drain_audio(second_sink)

    await_tone(second_sink, 250, 2_000)
    refute_receive {:DOWN, ^player_monitor, :process, ^observer_player, _}, 100

    replacement =
      plan
      |> issue_session(room, observer.participant_id)
      |> then(&connect(&1.session_id, "chat", false, :recvonly))

    await_tone(replacement, 250, 2_000)

    {retained_player, reconnected} =
      Map.fetch!(wait_players(room.incarnation_id), observer.participant_id)

    assert retained_player == observer_player

    assert Enum.sort(Map.keys(reconnected.sinks)) ==
             Enum.sort([second_sink.connection_id, replacement.connection_id])

    audience =
      Enum.map(audience, fn peer -> if peer == observer_client, do: replacement, else: peer end)

    assert {:ok, refreshed} = CallEngine.RoomAuthority.readiness_binding(authority)
    assert refreshed.attempt == pending.attempt
    assert refreshed.room == before.room
    refute Map.has_key?(refreshed.connections, observer_client.connection_id)

    for {id, connection} <- Map.delete(before.connections, observer_client.connection_id),
        do: assert(refreshed.connections[id] == connection)

    refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 0

    TestSpeechToTextTransport.deliver(
      support_stt,
      ~s({"type":"Connected","request_id":"multiple-support-ready","sequence_id":0})
    )

    await_sideband(support_client, "transfer.active", 3_000)
    await_transfer_progress(third_client, "completed")
    send_tone(support_client, 1_500, 1)
    for peer <- audience ++ [second_sink], do: assert_handoff_audio_order(peer, 1_500, 250)
    send_tone(caller_client, 500, 1)
    assert_handoff_audio_order(support_client, 500, 250)
    assert wait_players(room.incarnation_id) == %{}
    assert_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 2_000
  end

  test "native startup diagnostics follow independent STT and TTS acknowledgements" do
    handler = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler,
        [[:vxpipe, :call_engine, :startup, :progress], [:vxpipe, :call_engine, :startup, :stop]],
        &__MODULE__.handle_startup_diagnostic/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    plan = compile_plan(reception_model: "test:blocked", caller_speech_to_text?: true)
    assert {:ok, room} = CallEngine.start_call(plan)
    stop_room_on_exit(plan)
    assert_receive {:test_agent_runtime_model_preparing, model}, 2_000

    assert_receive {:native_startup, [:vxpipe, :call_engine, :startup, :progress], _,
                    %{blockers: [:model_inference]}},
                   1_000

    caller = Map.fetch!(plan.participants, "caller")

    client =
      plan
      |> issue_session(room, caller.participant_id)
      |> then(&connect(&1.session_id, "chat", false))

    assert :ok = send_client_ready(client)
    send(model, :release_test_agent_runtime_model)
    assert_receive {:test_tts_transport_started, voice, _}, 2_000
    assert_receive {:test_stt_transport_started, speech, _}, 2_000

    assert_receive {:native_startup, [:vxpipe, :call_engine, :startup, :progress], _,
                    %{blockers: [:speech_to_text, :text_to_speech]}},
                   2_000

    TestTextToSpeechTransport.deliver_control(
      voice,
      ~s({"type":"Connected","request_id":"voice-ready"})
    )

    assert_receive {:native_startup, [:vxpipe, :call_engine, :startup, :progress], _,
                    %{blockers: [:speech_to_text]}},
                   2_000

    assert client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
    assert :ok = send_rtvi_text(client, "held-for-stt")
    assert %{"id" => "held-for-stt"} = await_sideband(client, "error-response", 2_000)

    TestSpeechToTextTransport.deliver(
      speech,
      ~s({"type":"Connected","request_id":"speech-ready","sequence_id":0})
    )

    assert %{"type" => "bot-ready"} = await_sideband(client, "bot-ready", 2_000)

    assert_receive {:native_startup, [:vxpipe, :call_engine, :startup, :stop],
                    %{count: 1, duration: duration}, %{outcome: :ready, blockers: []}},
                   1_000

    assert duration >= 0
    refute_receive {:native_startup, [:vxpipe, :call_engine, :startup, :stop], _, _}
    refute_receive {:test_tts_transport_started, _, _}
    refute_receive {:test_stt_transport_started, _, _}
  end

  def handle_startup_diagnostic(event, measurements, metadata, receiver),
    do: send(receiver, {:native_startup, event, measurements, metadata})

  for mode <- [:defaults, :custom_url, :silent_caller, :silent_all] do
    @tag initial_wait: true, startup_wait_mode: mode
    test "initial #{mode} waiting gates model, voice, STT and room recording before one greeting",
         context do
      mode = context.startup_wait_mode
      {sounds, options} = startup_wait_configuration(mode)
      writer_readiness = :atomics.new(1, [])
      :ok = :atomics.put(writer_readiness, 1, 2)

      plan =
        compile_plan(
          reception_model: "test:blocked",
          caller_speech_to_text?: true,
          wait_sounds: sounds,
          reception_first_message: %{mode: "fixed", text: "Reception is ready."}
        )

      options =
        Keyword.put(options, :recording,
          enabled: true,
          targets: [:full_mix, :individual_tracks],
          writer: {CallEngine.TestRecordingWriter, observer: self(), readiness: writer_readiness},
          maximum_pull_frames: 20
        )

      assert {:ok, room} = CallEngine.start_call(plan, options)
      stop_room_on_exit(plan)
      assert_receive {:test_agent_runtime_model_preparing, model_preparer}, 2_000
      caller = Map.fetch!(plan.participants, "caller")

      client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      assert :ok = send_client_ready(client)
      assert_startup_wait(client, mode)
      assert :ok = send_rtvi_text(client, "held-during-call-setup")

      assert %{"id" => "held-during-call-setup"} =
               await_sideband(client, "error-response", 2_000)

      send(model_preparer, :release_test_agent_runtime_model)
      assert_receive {:test_tts_transport_started, voice, _}, 2_000
      assert_receive {:test_stt_transport_started, speech, _}, 2_000

      TestSpeechToTextTransport.deliver(
        speech,
        ~s({"type":"Connected","request_id":"initial-speech-ready","sequence_id":0})
      )

      assert_startup_wait(client, mode)
      refute_receive {:test_tts_control, ^voice, _speak}, 100

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"Connected","request_id":"initial-voice-ready"})
      )

      # Selected participant providers are now ready; the local room writer still is not.
      assert_startup_wait(client, mode)
      send_tone(client, 500, 1)
      assert :ok = send_rtvi_text(client, "held-for-recording")
      assert %{"id" => "held-for-recording"} = await_sideband(client, "error-response", 2_000)
      refute_receive {:test_tts_control, ^voice, _}, 100
      refute_receive {:test_stt_audio, ^speech, _}, 100
      refute_receive {:test_recording_chunk, _, _}, 100

      :ok = :atomics.put(writer_readiness, 1, 0)
      assert %{"type" => "bot-ready"} = await_sideband(client, "bot-ready", 2_000)
      assert_receive {:test_tts_control, ^voice, speak}, 2_000
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Reception is ready."}
      assert_receive {:test_tts_control, ^voice, _flush}, 2_000

      assert %{"data" => %{"text" => "Reception is ready."}} =
               await_sideband(client, "bot-output", 2_000)

      refute_receive {:test_stt_audio, ^speech, _held_audio}, 100
      refute_receive {:test_recording_chunk, _, _private_audio}, 100
      refute_receive {:test_stt_transport_started, _, _}, 100
      refute_receive {:test_tts_transport_started, _, _}, 100

      deliver_voice_tone(voice, "initial-greeting", 1_500)
      assert :ok = await_tone(client, 1_500, 2_000)

      assert %{"type" => "bot-stopped-speaking"} =
               await_sideband(client, "bot-stopped-speaking", 2_000)

      refute_tone(client, 250, 100)
      assert :ok = send_client_ready(client)
      assert %{"type" => "bot-ready"} = await_sideband(client, "bot-ready", 2_000)
      refute_receive {:test_tts_control, ^voice, _duplicate_greeting}, 100
      send_tone(client, 700, 11)
      assert_receive {:test_stt_audio, ^speech, _conversation}, 2_000
      assert_receive {:test_recording_chunk, _, _conversation}, 2_000

      if mode == :custom_url do
        assert_receive {:test_opening_audio_fetch, "https://media.example.com/handoff.wav", _}
        refute_receive {:test_opening_audio_fetch, _, _}
      end
    end
  end

  for failure <- [:readiness, :max_duration, :model] do
    test "native caller receives terminal signalling when startup fails at #{failure}" do
      model = if unquote(failure) == :model, do: "test:blocked-unavailable", else: "test:blocked"
      plan = compile_plan(reception_model: model)

      assert {:ok, room} =
               CallEngine.start_call(plan,
                 call_lifecycle: [
                   readiness_timeout_ms: 30_000,
                   idle_timeout_ms: 15_000,
                   timer: {CallEngine.TestCallLifecycleTimer, [observer: self()]}
                 ]
               )

      stop_room_on_exit(plan)
      assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 60_000}
      assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
      assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
      preparation_monitor = Process.monitor(preparer)
      caller = Map.fetch!(plan.participants, "caller")

      client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      [{connection, _}] =
        Registry.lookup(Vxpipe.Gateway.WebRTC.Registry, {:connection, client.connection_id})

      connection_monitor = Process.monitor(connection)
      assert :ok = send_client_ready(client)
      assert client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
      refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}, 100

      case unquote(failure) do
        :readiness -> CallEngine.TestCallLifecycleTimer.fire(readiness_timer)
        :max_duration -> CallEngine.TestCallLifecycleTimer.fire(maximum_timer)
        :model -> send(preparer, :release_test_agent_runtime_model)
      end

      assert %{"message" => %{"type" => "peerLeft"}} = await_sideband(client, "signalling", 2_000)
      assert_receive {:DOWN, ^preparation_monitor, :process, ^preparer, _}, 2_000
      assert_receive {:DOWN, ^connection_monitor, :process, ^connection, _}, 2_000
      peer = client.client
      channel = client.channel_ref
      refute_receive {:ex_webrtc, ^peer, {:data, ^channel, _}}, 100
      refute_receive {:test_tts_transport_started, _, _}, 100
    end
  end

  for mode <- [:custom_url, :defaults, :silent_caller] do
    @tag initial_wait: true, startup_wait_mode: mode
    test "opening file plays independently of model setup and waiting resumes after it with #{mode} waits",
         context do
      mode = context.startup_wait_mode
      {sounds, options} = startup_wait_configuration(mode)
      owner = self()
      opening_url = "https://media.example.com/initial-notice.wav"

      plan =
        compile_plan(
          reception_model: "test:blocked",
          reception_first_message: %{mode: "fixed", text: "Reception is ready."},
          opening_audio: %{type: "file_url", url: opening_url},
          wait_sounds: sounds
        )

      settings = Application.fetch_env!(:vxpipe_call_engine, CallEngine.Application)

      opening_settings = [
        fetcher:
          {CallEngine.TestOpeningAudioFetcher,
           [
             observer: owner,
             response: fn ->
               send(owner, {:opening_fetch_waiting, self()})

               receive do
                 :release_opening_file ->
                   {:ok,
                    %CallEngine.OpeningAudio.Download{
                      body: tone_wave(1_400),
                      content_type: "audio/wav"
                    }}
               end
             end
           ]}
      ]

      Application.put_env(
        :vxpipe_call_engine,
        CallEngine.Application,
        Keyword.put(settings, :opening_audio, opening_settings)
      )

      assert {:ok, room} = CallEngine.start_call(plan, options)
      stop_room_on_exit(plan)
      assert_receive {:test_agent_runtime_model_preparing, model_preparer}, 2_000
      caller = Map.fetch!(plan.participants, "caller")

      client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      assert :ok = send_client_ready(client)
      assert_receive {:opening_fetch_waiting, fetcher}, 2_000
      assert_startup_wait(client, mode)
      refute_receive {:test_tts_transport_started, _, _}, 100
      send(fetcher, :release_opening_file)
      assert :ok = await_tone(client, 1_400, 2_000)
      refute_tone(client, 1_000, 350)
      assert_startup_wait(client, mode)
      assert :ok = send_rtvi_text(client, "held-after-opening")

      assert %{"id" => "held-after-opening"} =
               await_sideband(client, "error-response", 2_000)

      send(model_preparer, :release_test_agent_runtime_model)
      assert_receive {:test_tts_transport_started, voice, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"Connected","request_id":"voice-ready-after-opening"})
      )

      assert_initial_opening_greeting(client, voice)
    end
  end

  for mode <- [:custom_url, :defaults, :silent_caller] do
    @tag initial_wait: true, startup_wait_mode: mode
    test "opening speech prepares independently and waiting continues until its first audio with #{mode} waits",
         context do
      mode = context.startup_wait_mode
      {sounds, options} = startup_wait_configuration(mode)

      plan =
        compile_plan(
          reception_model: "test:blocked",
          reception_first_message: %{mode: "fixed", text: "Reception is ready."},
          opening_audio: %{type: "text", text: "Opening notice.", text_to_speech: "test-voice"},
          wait_sounds: sounds
        )

      assert {:ok, room} = CallEngine.start_call(plan, options)
      stop_room_on_exit(plan)
      assert_receive {:test_agent_runtime_model_preparing, model_preparer}, 2_000
      assert_receive {:test_tts_transport_started, opening_voice, _}, 2_000
      opening_monitor = Process.monitor(opening_voice)

      TestTextToSpeechTransport.deliver_control(
        opening_voice,
        ~s({"type":"Connected","request_id":"opening-voice-ready"})
      )

      caller = Map.fetch!(plan.participants, "caller")

      client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      assert :ok = send_client_ready(client)
      assert_receive {:test_tts_control, ^opening_voice, speak}, 2_000
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Opening notice."}
      assert_receive {:test_tts_control, ^opening_voice, _flush}, 2_000
      assert_startup_wait(client, mode)

      TestTextToSpeechTransport.deliver_control(
        opening_voice,
        ~s({"type":"SpeechStarted","speech_id":"opening-notice"})
      )

      <<_header::binary-size(44), pcm::binary>> = tone_wave(1_400)
      TestTextToSpeechTransport.deliver_audio(opening_voice, pcm)

      TestTextToSpeechTransport.deliver_control(
        opening_voice,
        ~s({"type":"SpeechMetadata","speech_id":"opening-notice"})
      )

      assert :ok = await_tone(client, 1_400, 2_000)
      refute_tone(client, 1_000, 350)
      assert_startup_wait(client, mode)
      assert_receive {:DOWN, ^opening_monitor, :process, ^opening_voice, _}, 2_000
      send(model_preparer, :release_test_agent_runtime_model)
      assert_receive {:test_tts_transport_started, voice, _}, 2_000

      TestTextToSpeechTransport.deliver_control(
        voice,
        ~s({"type":"Connected","request_id":"voice-ready-after-opening"})
      )

      assert_initial_opening_greeting(client, voice)
    end
  end

  test "AI handoff waits independently for model and voice readiness before cues and greeting" do
    plan = compile_plan(agent_destination: true, billing_model: "test:blocked")
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
    assert_receive {:test_agent_runtime_model_preparing, model_preparer}, 2_000
    await_transfer_progress(client, "preparing")
    assert client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
    assert :ok = send_rtvi_text(client, "held-during-model-preparation")

    assert %{"id" => "held-during-model-preparation"} =
             await_sideband(client, "error-response", 2_000)

    refute_receive {:test_tts_transport_started, _destination_tts, _}, 50
    refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 50
    send(model_preparer, :release_test_agent_runtime_model)
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

  for mode <- [:defaults, :custom_url, :silent_caller, :silent_all] do
    @tag agent_wait_mode: mode
    test "AI handoff gates MCP and local tools with #{mode} waits", context do
      mode = context.agent_wait_mode
      {sounds, options} = agent_wait_configuration(mode)
      owner = self()
      remote_result = {:ok, %{"content" => [%{"type" => "text", "text" => "Customer found."}]}}

      remote_client =
        start_supervised!(
          {Agent, fn -> %{responses: [{:wait, owner, remote_result}], invocations: []} end}
        )

      {catalog, _binding} =
        CallEngine.RemoteMCPFixture.binding!(remote_client, self(), "private-mcp-sentinel",
          credential_generation: unique_id("ai-readiness"),
          client_config: [
            test_client: remote_client,
            test_observer: self(),
            private: "private-mcp-sentinel",
            test_gate_initialization: true
          ]
        )

      catalog_store = start_supervised!({CallEngine.RemoteMCP.CatalogStore, catalog: catalog})

      plan =
        compile_plan(
          agent_destination: true,
          caller_speech_to_text?: true,
          tenant_id: "tenant-demo",
          mcp_integrations: catalog,
          billing_tools: %{
            "customer_lookup" => %{type: "mcp", integration: "records", tool: "lookup_customer"},
            "test_agent_tool" => %{type: "host", tool: "test_agent_tool"}
          },
          billing_history: %{mode: "all_spoken"},
          wait_sounds: sounds
        )

      options =
        Keyword.merge(options,
          mcp_catalog_store: catalog_store,
          remote_mcp_connection_provider: CallEngine.TestRemoteMCPConnectionProvider,
          remote_mcp_protocol_client: CallEngine.TestRemoteMCPProtocolClient,
          recording: [
            enabled: true,
            targets: [:full_mix, :individual_tracks],
            writer: {CallEngine.TestRecordingWriter, observer: self()},
            maximum_pull_frames: 20
          ]
        )

      assert {:ok, room} = CallEngine.start_call(plan, options)
      stop_room_on_exit(plan)
      assert_receive {:test_tts_transport_started, source_tts, _}, 2_000
      source_monitor = Process.monitor(source_tts)

      TestTextToSpeechTransport.deliver_control(
        source_tts,
        ~s({"type":"Connected","request_id":"source-ready"})
      )

      caller = Map.fetch!(plan.participants, "caller")

      client =
        plan
        |> issue_session(room, caller.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      assert_receive {:test_stt_transport_started, speech, _}, 2_000
      speech_monitor = Process.monitor(speech)

      TestSpeechToTextTransport.deliver(
        speech,
        ~s({"type":"Connected","request_id":"caller-ready","sequence_id":0})
      )

      await_call_ready(client)

      if mode == :custom_url do
        assert_receive {:test_opening_audio_fetch, "https://media.example.com/handoff.wav", _},
                       1_000
      end

      assert :ok =
               send_rtvi_text(
                 client,
                 "transfer-with-tools",
                 true,
                 "Please connect me to billing."
               )

      assert_receive {:test_agent_runtime_stream, provider, _}, 2_000
      [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
      assert {:ok, before_transfer} = CallEngine.RoomAuthority.readiness_binding(authority)
      connection = Map.fetch!(before_transfer.connections, client.connection_id).pid
      assert {:ok, media} = GenServer.call(connection, :vxpipe_connection_readiness)

      assert {:ok, call} =
               ToolCall.new(
                 id: "to-billing",
                 name: "transfer",
                 arguments: %{"destination" => "billing"}
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
      send(provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_remote_mcp_initializing, remote_owner}, 2_000
      assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _}, 2_000
      assert {:ok, acknowledgement} = ModelResponse.new(text: "Late source acknowledgement.")
      send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, acknowledgement}})
      progress = await_transfer_progress(client, "preparing")
      assert_startup_wait(client, mode)
      assert :ok = send_rtvi_text(client, "held-during-mcp", false, "held-during-mcp")
      assert %{"id" => "held-during-mcp"} = await_sideband(client, "error-response", 2_000)
      send_tone(client, 500, 1)
      refute_receive {:test_stt_audio, ^speech, _held_input}, 100
      refute_receive {:test_recording_chunk, _, _private_audio}, 100
      refute_receive {:test_tts_transport_started, _destination, _}, 0
      refute_receive {:test_tts_control, ^source_tts, _late_speech}, 0
      assert Agent.get(remote_client, & &1.invocations) == []
      send(remote_owner, :test_remote_mcp_initialized)
      assert_receive {:test_tts_transport_started, destination_tts, _}, 2_000

      assert {:ok, remote_resource, :ready} =
               CallEngine.RemoteMCP.IntegrationOwner.readiness(remote_owner)

      tools =
        CallEngine.AgentActivationSupervisor.whereis_child(
          remote_resource.binding,
          :invocation_registry
        )

      assert {:ok, tool_resource, :ready} = CallEngine.Tool.InvocationRegistry.readiness(tools)
      token = pause_tool_readiness(tools)

      try do
        assert_receive {:tool_readiness_waiting, ^token}, 2_000

        TestTextToSpeechTransport.deliver_control(
          destination_tts,
          ~s({"type":"Connected","request_id":"destination-ready"})
        )

        assert :ok = send_rtvi_text(client, "held-during-tools", false, "held-during-tools")
        assert %{"id" => "held-during-tools"} = await_sideband(client, "error-response", 2_000)
        refute_receive {:test_tts_control, ^destination_tts, _greeting}, 50

        refute_receive {:test_agent_runtime_stream, _model,
                        %{messages: [%{content: "Handle billing requests."} | _]}},
                       0

        refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 0
        refute_native_activation(client, System.monotonic_time(:millisecond) + 50)
        assert Agent.get(remote_client, & &1.invocations) == []
      after
        send(tools, {:continue_tool_readiness, token})
      end

      completed = await_transfer_progress(client, "completed")
      assert completed["attempt_id"] == progress["attempt_id"]
      assert_receive {:test_tts_control, ^destination_tts, speak}, 2_000
      assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Billing is ready."}
      assert_receive {:test_tts_control, ^destination_tts, _flush}, 2_000
      assert_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 2_000
      refute_receive {:test_stt_transport_started, _replacement, _}, 0
      refute_receive {:DOWN, ^speech_monitor, :process, ^speech, _}, 0
      refute_receive {:test_stt_audio, ^speech, _held_input}, 0
      refute_receive {:test_recording_chunk, _, _private_audio}, 0

      assert {:ok, after_transfer} = CallEngine.RoomAuthority.readiness_binding(authority)
      assert after_transfer.room == before_transfer.room
      assert after_transfer.connections == before_transfer.connections

      assert Map.fetch!(after_transfer.participants, caller.participant_id) ==
               Map.fetch!(before_transfer.participants, caller.participant_id)

      assert {:ok, retained_media} = GenServer.call(connection, :vxpipe_connection_readiness)
      assert retained_media.output == media.output
      assert retained_media.room_input == media.room_input
      assert retained_media.room_output == media.room_output
      assert retained_media.attachment.media_ingress == media.attachment.media_ingress

      assert {:ok, ^remote_resource, :ready} =
               CallEngine.RemoteMCP.IntegrationOwner.readiness(remote_owner)

      assert {:ok, ^tool_resource, :ready} = CallEngine.Tool.InvocationRegistry.readiness(tools)
      refute_receive {:test_tts_transport_started, _replacement, _}, 0

      deliver_voice_tone(destination_tts, "billing-greeting", 1_500)
      assert_handoff_audio_order(client, 1_500, if(mode == :custom_url, do: 250))
      await_agent_greeting_end(client, System.monotonic_time(:millisecond) + 2_000)
      assert :ok = send_client_ready(client)
      refute_receive {:test_tts_control, ^destination_tts, _duplicate_greeting}, 0
      refute_native_activation(client, System.monotonic_time(:millisecond) + 50)
      send_tone(client, 500, 11)
      assert_receive {:test_stt_audio, ^speech, _conversation}, 2_000
      assert_receive {:test_recording_chunk, _, _conversation}, 2_000

      assert :ok =
               send_rtvi_text(client, "use-billing-tools", false, "Look up my billing account.")

      assert_receive {:test_agent_runtime_stream, billing_provider,
                      %{correlation: %{correlation_id: "use-billing-tools"}} = request},
                     2_000

      assert Enum.sort(Enum.map(request.tools, & &1.name)) == [
               "customer_lookup",
               "test_agent_tool"
             ]

      contents = Enum.map(request.messages, & &1.content)
      assert "Please connect me to billing." in contents
      assert "Billing is ready." in contents

      for marker <- [
            "held-during-mcp",
            "held-during-tools",
            "Late source acknowledgement.",
            "handoff.wav",
            "private-mcp-sentinel"
          ] do
        refute inspect(request) =~ marker
      end

      assert {:ok, lookup} =
               ToolCall.new(
                 id: "lookup",
                 name: "customer_lookup",
                 arguments: %{"customer_id" => "test-customer"}
               )

      assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [lookup])
      send(billing_provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:test_remote_mcp_invocation_started, execution}, 2_000

      assert [%{name: "lookup_customer", arguments: %{"customer_id" => "test-customer"}}] =
               Agent.get(remote_client, & &1.invocations)

      send(execution, :release_test_remote_mcp)
      refute_receive {:test_opening_audio_fetch, _url, _limits}, 0
    end
  end

  for {wait_mode, last_ready, loss_at} <- [
        {:defaults, :destination, nil},
        {:custom_url, :destination, nil},
        {:live_url, :destination, nil},
        {:silent_caller, :destination, nil},
        {:silent_all, :destination, nil},
        {:custom_url, :participant, nil},
        {:silent_all, :participant, nil},
        {:custom_url, :recording, nil},
        {:silent_all, :recording, nil},
        {:silent_all, :recording, :recording_denied},
        {:silent_all, :recording, :recording_unrelated},
        {:silent_all, :participant, :preparation},
        {:silent_all, :recording, :preparation},
        {:silent_all, :participant, :adopt},
        {:silent_all, :recording, :adopt},
        {:silent_all, :participant, :release},
        {:silent_all, :recording, :release},
        {:silent_all, :destination, :preparation},
        {:silent_all, :destination, :adopt},
        {:silent_all, :destination, :release}
      ] do
    if wait_mode == :live_url do
      @tag :integration
    end

    outcome =
      case {last_ready, loss_at} do
        {:destination, :preparation} ->
          "recovers after preparation loss"

        {_kind, nil} ->
          "then relays conversation"

        {_kind, change} when change in [:recording_denied, :recording_unrelated] ->
          "reconciles #{change} policy"

        {_kind, stage} ->
          "closes after #{stage} loss"
      end

    @tag wait_mode: wait_mode, last_ready: last_ready, loss_at: loss_at
    test "human handoff gates #{last_ready} and #{outcome} with #{wait_mode} waits",
         %{
           wait_mode: mode,
           last_ready: last_ready,
           loss_at: loss_at
         } do
      alias Vxpipe.CallEngine.MediaPolicy.Authority

      recording_change = if loss_at in [:recording_denied, :recording_unrelated], do: loss_at
      loss_at = if recording_change, do: nil, else: loss_at
      {wait_sounds, options} = wait_configuration(mode)
      writer_readiness = :atomics.new(1, [])

      plan =
        compile_plan(
          wait_sounds: wait_sounds,
          observer_speech_to_text?: true,
          observer_policy: %{},
          restriction_policy:
            if(recording_change == :recording_unrelated, do: %{}, else: %{record_audio: false})
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      observer = Map.fetch!(plan.participants, "observer")

      assert {:ok, room} =
               CallEngine.start_call(
                 plan,
                 Keyword.put(options, :recording,
                   enabled: true,
                   targets: [:full_mix, :individual_tracks],
                   writer:
                     {CallEngine.TestRecordingWriter,
                      observer: self(), readiness: writer_readiness},
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

      observer_client =
        plan
        |> issue_session(room, observer.participant_id)
        |> then(&connect(&1.session_id, "chat", false))

      assert_receive {:test_stt_transport_started, remaining_stt, _}, 2_000

      restriction_client =
        if recording_change do
          restriction = Map.fetch!(plan.participants, "recording-restriction")

          assert {:ok, restriction_join} =
                   CallEngine.Command.JoinParticipant.new(
                     tenant_id: plan.tenant_id,
                     actor_id: plan.actor_id,
                     room_id: plan.room_id,
                     participant_id: restriction.participant_id,
                     role: :human,
                     deadline: DateTime.add(DateTime.utc_now(), 5, :second)
                   )

          assert {:ok, _} = CallEngine.join_participant(restriction_join)

          client =
            plan
            |> issue_session(room, restriction.participant_id)
            |> then(&connect(&1.session_id, "chat", false))

          policy_authority = Authority.whereis(room.incarnation_id)
          assert {:ok, _} = Authority.leave(policy_authority, restriction.participant_id)
          client
        end

      :ok = :atomics.put(writer_readiness, 1, 2)

      recovers? = last_ready == :destination and loss_at == :preparation
      assert :ok = send_rtvi_text(caller_client, "ready-transfer", recovers?)
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

      briefing_monitor = Process.monitor(briefing_tts)

      if recovers? do
        assert_receive {:test_agent_runtime_stream, acknowledgement_provider, _}, 2_000
        assert {:ok, acknowledgement} = ModelResponse.new(text: "I am connecting support.")
        send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, acknowledgement}})
      end

      # Every existing listener waits from authorization, before the destination connects.
      for audience_client <- [caller_client, observer_client] do
        case mode do
          mode when mode in [:silent_caller, :silent_all] ->
            refute_audio(audience_client, 150)

          mode when mode in [:custom_url, :live_url] ->
            await_tone(audience_client, 250, 2_000)

          :defaults ->
            assert audience_client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
        end
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
      observer_binding = Map.fetch!(binding.connections, observer_client.connection_id)
      {:ok, observer_media} = GenServer.call(observer_binding.pid, :vxpipe_connection_readiness)
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

      assert_receive {:DOWN, ^briefing_monitor, :process, ^briefing_tts, _reason}, 1_000

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

        mode when mode in [:custom_url, :live_url] ->
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

      releases = %{
        destination: fn ->
          TestSpeechToTextTransport.deliver(
            joining_stt,
            ~s({"type":"Connected","request_id":"ready-human-stt","sequence_id":0})
          )
        end,
        participant: fn ->
          TestSpeechToTextTransport.deliver(
            remaining_stt,
            ~s({"type":"Connected","request_id":"ready-remaining-stt","sequence_id":0})
          )
        end,
        recording: fn -> :atomics.put(writer_readiness, 1, 0) end
      }

      for {kind, ready} <- releases, kind != last_ready, do: ready.()
      blocker = if last_ready == :recording, do: "recording", else: "speech_to_text"

      assert %{"attempt_id" => ^attempt_id} =
               await_transfer_progress(caller_client, "preparing", [blocker])

      assert :ok = send_rtvi_text(caller_client, "held-for-last-resource")

      assert %{"id" => "held-for-last-resource"} =
               await_sideband(caller_client, "error-response", 2_000)

      send_tone(observer_client, 1_750, 1)
      refute_tone(caller_client, 1_750, 100)
      refute_tone(support_client, 1_750, 100)
      refute_receive {:test_stt_audio, ^remaining_stt, _held_input}, 100
      refute_receive {:test_stt_audio, ^joining_stt, _held_input}, 100
      refute_receive {:test_recording_chunk, _, _private_audio}, 100
      refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _}, 100
      assert Authority.snapshot(binding.policy_authority) == policy

      if loss_at do
        authority_monitor = Process.monitor(room_authority)

        connection_monitors =
          Enum.map(binding.connections, fn {_id, bound} ->
            {bound.pid, Process.monitor(bound.pid)}
          end)

        fail_resource = fn ->
          case last_ready do
            kind when kind in [:destination, :participant] ->
              transport = if kind == :destination, do: joining_stt, else: remaining_stt
              monitor = Process.monitor(transport)
              TestSpeechToTextTransport.disconnect(transport, :test_handoff_loss)
              assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}, 1_000

            :recording ->
              :atomics.put(writer_readiness, 1, 1)
          end
        end

        if loss_at == :preparation do
          fail_resource.()
        else
          token = pause_native_gate(connection, loss_at)
          Map.fetch!(releases, last_ready).()
          assert_receive {:native_gate_waiting, ^token}, 2_000

          try do
            assert :sys.get_state(private.output).held? == (loss_at != :release)
            fail_resource.()
          after
            send(connection, {:continue_native_gate, token})
          end
        end

        if recovers? do
          # The failed destination is being disconnected; the retained caller owns
          # the reliable recovery-status assertion.
          assert %{"reason" => failure_reason} =
                   await_transfer_progress(caller_client, "recovering")

          # The speech owner can report provider loss directly, or the readiness
          # collector can observe the failed media binding first.
          assert failure_reason in ["speech_to_text_unavailable", "media_unavailable"]

          await_recovered(room_authority, System.monotonic_time(:millisecond) + 2_000)

          assert %{"phase" => "recovered", "reason" => ^failure_reason} =
                   await_transfer_progress(caller_client, "recovered")

          refute_receive {:DOWN, ^authority_monitor, :process, ^room_authority, _reason}, 50
          refute_receive {:DOWN, ^source_monitor, :process, ^source_tts, _reason}, 50
          assert {:ok, recovered} = CallEngine.RoomAuthority.readiness_binding(room_authority)
          assert recovered.room == binding.room

          assert recovered.connections ==
                   Map.delete(binding.connections, support_client.connection_id)

          for peer <- [caller_client, observer_client] do
            actor = Map.fetch!(recovered.connections, peer.connection_id).pid
            assert :sys.get_state(actor).handoff_gate == nil
          end

          assert_receive {:test_agent_runtime_stream, response_provider, _}, 2_000
          assert {:ok, response} = ModelResponse.new(text: "We can continue.")
          send(response_provider, {:test_agent_runtime_response, {:ok, response}})

          assert %{"data" => %{"text" => "We can continue."}} =
                   await_sideband(observer_client, "bot-output", 2_000)

          assert :sys.get_state(observer_binding.pid).rtvi_turn_state.active_spoken_output == nil
          assert_receive {:test_tts_control, ^source_tts, speak}, 2_000
          assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "We can continue."}
          assert_receive {:test_tts_control, ^source_tts, _flush}, 2_000
          deliver_voice_tone(source_tts, "whole-room-recovery", 1_500)
          assert_handoff_audio_order(caller_client, 1_500, nil)
          # Synthesized replies use the requesting caller's output. Verify the
          # remaining listener's cue against the room audio it actually receives.
          send_tone(caller_client, 500, 1)
          assert_handoff_audio_order(observer_client, 500, nil)
          refute_receive {:test_stt_audio, ^remaining_stt, _held_input}, 100
          send_tone(observer_client, 1_750, 11)
          await_tone(caller_client, 1_750, 2_000)
          assert_receive {:test_stt_audio, ^remaining_stt, _conversation}, 2_000

          for participant_id <- [caller.participant_id, observer.participant_id] do
            assert_receive {:test_recording_writer_opened, _writer, _recorder,
                            %{participant_id: ^participant_id, stream_id: stream_id}},
                           2_000

            assert_receive {:test_recording_chunk, ^stream_id, chunk}, 2_000
            assert byte_size(chunk.payload) > 0
          end

          refute_receive {:test_stt_transport_started, _replacement, _}, 50
          refute_receive {:test_tts_transport_started, _replacement, _}, 50
          refute_native_activation(support_client, System.monotonic_time(:millisecond) + 100)
        else
          assert_receive {:DOWN, ^authority_monitor, :process, ^room_authority, reason}, 2_000
          assert reason in [:shutdown, :handoff_recovery_failed, :handoff_release_failed]

          for {actor, monitor} <- connection_monitors do
            assert_receive {:DOWN, ^monitor, :process, ^actor, _reason}, 2_000
          end

          for peer <- [caller_client, observer_client, support_client] do
            refute_native_activation(peer, System.monotonic_time(:millisecond) + 100)
          end

          refute_receive {:test_stt_transport_started, _replacement, _}, 50
          refute_receive {:test_tts_transport_started, _redial, _}, 50
          assert_receive {:DOWN, ^source_monitor, :process, ^source_tts, _reason}, 2_000
        end
      else
        retained_recording_stream =
          if recording_change do
            support_id = support.participant_id

            assert_receive {:test_recording_writer_opened, private_writer, private_writer,
                            %{participant_id: ^support_id, stream_id: stream_id}},
                           2_000

            writer_monitor = Process.monitor(private_writer)
            pending = :sys.get_state(room_authority).pending_participant_transfer
            token = pause_native_gate(connection, :adopt)
            restriction = Map.fetch!(plan.participants, "recording-restriction")

            try do
              assert {:ok, _} =
                       Authority.admit(binding.policy_authority, restriction.participant_id)

              if recording_change == :recording_denied do
                assert_receive {:DOWN, ^writer_monitor, :process, ^private_writer, _}, 2_000
              else
                Map.fetch!(releases, last_ready).()
              end

              assert_receive {:native_gate_waiting, ^token}, 2_000
              refreshed = :sys.get_state(room_authority).pending_participant_transfer
              assert refreshed.task.pid == pending.task.pid
              assert refreshed.deadline_ms == pending.deadline_ms
              assert {:ok, current} = CallEngine.RoomAuthority.readiness_binding(room_authority)
              assert current.room == binding.room
              source_id = Map.fetch!(plan.participants, "reception").participant_id

              assert Map.fetch!(current.participants, source_id) ==
                       Map.fetch!(binding.participants, source_id)

              if recording_change == :recording_unrelated do
                refute_receive {:DOWN, ^writer_monitor, :process, ^private_writer, _}, 0

                refute_receive {:test_recording_writer_opened, _replacement, _source,
                                %{participant_id: ^support_id}},
                               0
              end
            after
              send(connection, {:continue_native_gate, token})
            end

            stream_id
          else
            Map.fetch!(releases, last_ready).()
            nil
          end

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
        assert final.room == binding.room
        assert Map.fetch!(final.connections, observer_client.connection_id) == observer_binding

        assert {:ok, retained_observer} =
                 GenServer.call(observer_binding.pid, :vxpipe_connection_readiness)

        assert retained_observer.output == observer_media.output
        assert retained_observer.room_input == observer_media.room_input
        assert retained_observer.room_output == observer_media.room_output
        assert {:ok, _binding, :ready} = Vxpipe.Gateway.WebRTC.Connection.readiness(connection)

        refute_receive {:test_stt_audio, ^joining_stt, _held_or_private_audio}, 100
        refute_receive {:test_recording_chunk, _stream, _private_audio}, 100
        refute_receive {:test_opening_audio_fetch, _url, _limits}

        # Inspect the queued cue and subsequent conversation together: no wait may follow
        # the cue, and no cue may follow the first conversation frame on either peer.
        wait_frequency = if mode in [:custom_url, :live_url], do: 250
        send_tone(caller_client, 500, 1)
        assert_handoff_audio_order(support_client, 500, wait_frequency)
        assert_handoff_audio_order(observer_client, 500, wait_frequency)

        if restriction_client,
          do: assert_handoff_audio_order(restriction_client, 500, wait_frequency)

        send_tone(support_client, 1_500, 11)
        assert_handoff_audio_order(caller_client, 1_500, wait_frequency)
        assert_receive {:test_stt_audio, ^joining_stt, _conversation_audio}, 2_000
        refute_receive {:test_stt_audio, ^remaining_stt, _held_audio}, 100
        send_tone(observer_client, 1_750, 11)
        await_tone(caller_client, 1_750, 2_000)
        await_tone(support_client, 1_750, 2_000)
        assert_receive {:test_stt_audio, ^remaining_stt, _conversation_audio}, 2_000
        caller_id = caller.participant_id
        support_id = support.participant_id

        if recording_change == :recording_denied do
          assert :atomics.get(writer_readiness, 1) == 2

          assert {:ok, resources} =
                   CallEngine.RoomRecording.readiness_resources(binding.room.recording)

          refute Enum.any?(resources, &(&1.kind == :recording_writer))
          refute_receive {:test_recording_chunk, _stream, _chunk}, 100
        else
          for participant_id <- [caller_id, support_id, observer.participant_id] do
            stream_id =
              if recording_change == :recording_unrelated and participant_id == support_id do
                retained_recording_stream
              else
                assert_receive {:test_recording_writer_opened, _writer, _recorder,
                                %{participant_id: ^participant_id, stream_id: opened_stream}},
                               2_000

                opened_stream
              end

            assert_receive {:test_recording_chunk, ^stream_id, chunk}, 2_000
            assert byte_size(chunk.payload) > 0
          end
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
  end

  for preparation <- [
        :none,
        :before_policy_change,
        :during_readiness,
        :during_unrelated_change,
        :after_adoption,
        :after_unrelated_adoption,
        :after_speech_adoption,
        :release_policy_change,
        :release_unrelated_change,
        :release_deadline,
        :release_speech_loss
      ] do
    @tag preparation: preparation
    test "human handoff handles #{preparation} preparation", %{
      preparation: preparation
    } do
      restriction = %{transcript_routes: %{}, save_transcripts: false}

      plan =
        compile_plan(
          support_policy: if(preparation == :none, do: restriction, else: %{}),
          observer_policy:
            case preparation do
              mode
              when mode in [
                     :during_unrelated_change,
                     :after_unrelated_adoption,
                     :release_unrelated_change,
                     :release_deadline,
                     :release_speech_loss
                   ] ->
                %{}

              :after_speech_adoption ->
                %{save_transcripts: false}

              _restricted ->
                restriction
            end
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = CallEngine.start_call(plan)

      assert {:ok, room_monitor} =
               CallEngine.monitor_room(plan.tenant_id, plan.room_id, room.incarnation_id)

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
        if preparation != :none do
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
        if preparation == :before_policy_change do
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
        if preparation in [
             :during_readiness,
             :during_unrelated_change,
             :after_adoption,
             :after_unrelated_adoption,
             :after_speech_adoption,
             :release_policy_change,
             :release_unrelated_change,
             :release_deadline,
             :release_speech_loss
           ] do
          assert_receive {:test_stt_transport_started, transport, _}, 2_000

          assert %{"data" => %{"phase" => "preparing", "blockers" => blockers}} =
                   await_sideband(support_client, "transfer.progress", 2_000)

          assert "speech_to_text" in blockers

          before = capture_private_media(plan, support_client, attempt)
          {policy_authority, observer} = policy_change

          if preparation in [
               :after_adoption,
               :after_unrelated_adoption,
               :after_speech_adoption,
               :release_policy_change,
               :release_unrelated_change,
               :release_deadline,
               :release_speech_loss
             ] do
            {media, _monitors, _connections} = before

            action =
              if preparation in [
                   :release_policy_change,
                   :release_unrelated_change,
                   :release_deadline,
                   :release_speech_loss
                 ],
                 do: :release,
                 else: :adopt

            token = pause_native_gate(media.instance, action)

            TestSpeechToTextTransport.deliver(
              transport,
              ~s({"type":"Connected","request_id":"ready-before-adoption","sequence_id":0})
            )

            assert_receive {:native_gate_waiting, ^token}, 2_000

            try do
              case preparation do
                :release_deadline ->
                  [{authority, _}] =
                    Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

                  pending = :sys.get_state(authority).pending_participant_transfer
                  send(authority, {:vxpipe_participant_transfer_deadline, pending.task.ref})

                  assert %{"reason" => "timeout"} =
                           await_terminal_transfer_failure(caller_client, attempt)

                :release_speech_loss ->
                  TestSpeechToTextTransport.disconnect(transport, :test_release_failure)

                  assert %{"reason" => "speech_to_text_unavailable"} =
                           await_terminal_transfer_failure(caller_client, attempt)

                _policy_change ->
                  assert {:ok, _policy} =
                           CallEngine.MediaPolicy.Authority.admit(policy_authority, observer)
              end
            after
              send(media.instance, {:continue_native_gate, token})
            end

            if preparation == :after_speech_adoption do
              assert_receive {:test_stt_transport_started, replacement, _}, 1_000
              assert replacement != transport

              assert :ok =
                       await_destination_blocker(
                         support_client,
                         "speech_to_text",
                         System.monotonic_time(:millisecond) + 2_000
                       )

              TestSpeechToTextTransport.deliver(
                replacement,
                ~s({"type":"Connected","request_id":"changed-native-speech","sequence_id":0})
              )
            end
          else
            assert {:ok, _policy} =
                     CallEngine.MediaPolicy.Authority.admit(policy_authority, observer)
          end

          if preparation == :during_unrelated_change do
            TestSpeechToTextTransport.deliver(
              transport,
              ~s({"type":"Connected","request_id":"retained-after-policy-change","sequence_id":0})
            )
          end

          before
        else
          prior_media
        end

      if preparation in [
           :release_policy_change,
           :release_unrelated_change,
           :release_deadline,
           :release_speech_loss
         ] do
        assert_receive {:DOWN, ^room_monitor, :process, _room, reason}, 2_000

        if preparation == :release_speech_loss,
          do: assert(reason in [:handoff_release_failed, :shutdown]),
          else: assert(reason == :handoff_release_failed)

        {_media, _monitors, connections} = prior_media

        for {_id, connection} <- connections do
          monitor = Process.monitor(connection.instance)
          assert_receive {:DOWN, ^monitor, :process, _, _reason}, 2_000
        end

        refute_native_activation(support_client, System.monotonic_time(:millisecond) + 100)
        refute_receive {:test_tts_transport_started, _recovery_or_redial, _}, 50
      else
        assert %{"data" => %{"attempt_id" => ^attempt}} =
                 await_sideband(support_client, "transfer.active", 2_000)

        [{authority, _}] =
          Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

        assert {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)
        joining = Map.fetch!(binding.connections, support_client.connection_id).pid
        assert {:ok, media} = GenServer.call(joining, :vxpipe_connection_readiness)
        assert media.attachment.admission == :main

        if preparation not in [
             :during_unrelated_change,
             :after_adoption,
             :after_unrelated_adoption,
             :after_speech_adoption,
             :release_policy_change,
             :release_unrelated_change,
             :release_deadline,
             :release_speech_loss
           ],
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
            if preparation in [
                 :during_unrelated_change,
                 :after_adoption,
                 :after_unrelated_adoption,
                 :after_speech_adoption,
                 :release_policy_change,
                 :release_unrelated_change,
                 :release_deadline,
                 :release_speech_loss
               ] do
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
  end

  for loss <- [
        :destination,
        :destination_output_clear,
        :briefing_destination,
        :briefing_voice,
        :briefing_timeout,
        :acceptance_timeout,
        :phase,
        :wait_player,
        :agent_destination,
        :agent_model
      ] do
    @tag recovery_loss: loss
    test "recovers the held caller after #{loss} loss without replacing source media" do
      agent_destination? = unquote(loss) in [:agent_destination, :agent_model]

      {wait_sounds, wait_options} =
        wait_configuration(
          if unquote(loss) in [:destination, :destination_output_clear],
            do: :custom_url,
            else: :defaults
        )

      plan =
        compile_plan(
          agent_destination: agent_destination?,
          wait_sounds: wait_sounds,
          transfer_timeout_ms:
            if(unquote(loss) in [:briefing_timeout, :acceptance_timeout], do: 5_000, else: 30_000),
          transfer_notice: "Private desk notice: verify the account before discussing details.",
          billing_model:
            if(unquote(loss) == :agent_model,
              do: "test:blocked-unavailable",
              else: "test:scripted"
            )
        )

      caller = Map.fetch!(plan.participants, "caller")
      support = Map.fetch!(plan.participants, "human-support")
      assert {:ok, room} = CallEngine.start_call(plan, wait_options)
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

      destination_preparer =
        if unquote(loss) == :agent_model do
          assert_receive {:test_agent_runtime_model_preparing, preparer}, 2_000
          preparer
        else
          assert_receive {:test_tts_transport_started, preparer, _}, 2_000
          preparer
        end

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

          if unquote(loss) in [:destination, :destination_output_clear, :acceptance_timeout] do
            assert_receive {:test_tts_control, ^destination_preparer, speak}, 2_000
            assert String.contains?(JSON.decode!(speak)["text"], "Private desk notice:")
            assert_receive {:test_tts_control, ^destination_preparer, _flush}, 2_000
            deliver_voice_tone(destination_preparer, "private-recovery-briefing", 750)
            assert :ok = await_tone(client, 750, 2_000)

            assert %{"type" => "transfer.acceptance_ready"} =
                     await_sideband(client, "transfer.acceptance_ready", 2_000)

            assert :ok =
                     send_rtvi_text(
                       caller_client,
                       "held-private-turn",
                       false,
                       "Held input marker."
                     )

            assert %{"id" => "held-private-turn"} =
                     await_sideband(caller_client, "error-response", 2_000)

            refute_tone(caller_client, 750, 100)
          end

          client
        end

      {:ok, binding} = CallEngine.RoomAuthority.readiness_binding(authority)
      pending = :sys.get_state(authority).pending_participant_transfer
      phase_monitor = Process.monitor(pending.task.pid)

      recovery_gate =
        if unquote(loss) == :destination_output_clear,
          do: pause_native_gate(caller_connection, :recover)

      case unquote(loss) do
        :agent_model ->
          send(destination_preparer, :release_test_agent_runtime_model)

        :agent_destination ->
          TestTextToSpeechTransport.disconnect(destination_preparer, :test_destination_failed)

        loss when loss in [:destination, :destination_output_clear, :briefing_destination] ->
          GenServer.stop(
            Map.fetch!(binding.connections, support_client.connection_id).pid,
            :normal
          )

        :briefing_voice ->
          TestTextToSpeechTransport.disconnect(destination_preparer, :test_briefing_failed)

        loss when loss in [:briefing_timeout, :acceptance_timeout] ->
          # Let the configured total attempt timer expire at the actual lifecycle boundary.
          assert pending.briefing == if(loss == :briefing_timeout, do: :playing, else: :completed)

        :phase ->
          Process.exit(pending.task.pid, :kill)

        :wait_player ->
          {:ok, phase} =
            CallEngine.RoomAuthority.ParticipantTransfer.Phase.scope(pending.task.pid)

          [player] = Map.values(phase.audience.waits)
          Process.exit(player, :kill)
      end

      if recovery_gate,
        do: clear_during_recovery_readiness(caller_connection, before.output, recovery_gate)

      release_timeout =
        if unquote(loss) in [:briefing_timeout, :acceptance_timeout], do: 6_000, else: 2_000

      unless agent_destination?,
        do: assert_receive(:destination_admission_released, release_timeout)

      assert_receive {:DOWN, ^phase_monitor, :process, _, _}, 2_000
      await_recovered(authority, System.monotonic_time(:millisecond) + 2_000)

      assert %{"phase" => "recovered", "reason" => reason} =
               await_transfer_progress(caller_client, "recovered")

      case unquote(loss) do
        loss when loss in [:briefing_timeout, :acceptance_timeout] -> assert reason == "timeout"
        :briefing_destination -> assert reason == "destination_disconnected"
        :briefing_voice -> assert reason == "text_to_speech_unavailable"
        _existing_loss -> :ok
      end

      unless agent_destination? do
        refute_native_activation(support_client, System.monotonic_time(:millisecond) + 50)
        refute_receive :destination_admission_released, 0
      end

      assert :ok = await_tone(caller_client, 1_000, 2_000)
      refute_receive {:DOWN, ^caller_monitor, :process, ^caller_connection, _}, 50
      {:ok, after_recovery} = GenServer.call(caller_connection, :vxpipe_connection_readiness)
      assert after_recovery.output == before.output
      assert after_recovery.room_input == before.room_input
      assert after_recovery.room_output == before.room_output
      assert :sys.get_state(caller_connection).handoff_gate == nil
      refute_receive {:test_tts_transport_started, _replacement, _}, 50

      # Finish the scripted response to the failed tool before starting another caller turn.
      assert_receive {:test_agent_runtime_stream, recovery_provider, recovery_request}, 2_000
      assert_private_transfer_history(recovery_request)
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
                      %{correlation: %{correlation_id: "after-recovery"}} = retry_request},
                     2_000

      assert_private_transfer_history(retry_request)

      if unquote(loss) in [:destination, :destination_output_clear] do
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
      |> then(&connect(&1.session_id, "chat", false))

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
    await_call_ready(caller_client)

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

  defp await_destination_blocker(connection, kind, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    %{"data" => %{"blockers" => blockers}} =
      await_sideband(connection, "transfer.progress", remaining, "preparing")

    if kind in blockers,
      do: :ok,
      else: await_destination_blocker(connection, kind, deadline)
  end

  defp await_terminal_transfer_failure(connection, attempt) do
    await_terminal_transfer_failure(
      connection,
      attempt,
      System.monotonic_time(:millisecond) + 2_000
    )
  end

  defp await_terminal_transfer_failure(connection, attempt, deadline) do
    message =
      await_sideband(
        connection,
        "server-message",
        max(deadline - System.monotonic_time(:millisecond), 0)
      )

    case message do
      %{
        "data" => %{
          "t" => "vxpipe.transfer",
          "d" => %{"attempt_id" => ^attempt, "phase" => phase} = progress
        }
      } ->
        refute phase in ["recovering", "recovered", "completed"],
               "a failed release attempted recovery or reported success"

        if phase == "failed",
          do: progress,
          else: await_terminal_transfer_failure(connection, attempt, deadline)

      _other ->
        await_terminal_transfer_failure(connection, attempt, deadline)
    end
  end

  defp refute_native_activation(connection, deadline) do
    client = connection.client
    channel = connection.channel_ref

    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} ->
        message = JSON.decode!(payload)
        refute message["type"] == "transfer.active"

        refute match?(
                 %{
                   "type" => "server-message",
                   "data" => %{"t" => "vxpipe.transfer", "d" => %{"phase" => "completed"}}
                 },
                 message
               )

        refute_native_activation(connection, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> :ok
    end
  end

  defp pause_native_gate(connection, action) do
    token = make_ref()
    owner = self()

    assert :ok =
             :sys.install(
               connection,
               {token,
                fn state, event, _process ->
                  case {state, event} do
                    {:done, _event} ->
                      :done

                    {_state,
                     {:in, {:"$gen_call", _from, {:vxpipe_handoff_gate, ^action, _scope}}}} ->
                      send(owner, {:native_gate_waiting, token})

                      receive do
                        {:continue_native_gate, ^token} -> :done
                      after
                        1_000 -> :done
                      end

                    _other ->
                      state
                  end
                end, nil}
             )

    token
  end

  defp clear_during_recovery_readiness(connection, output, gate) do
    alias Vxpipe.CallEngine.Media.OutputSink
    alias Vxpipe.CallEngine.Readiness.Collector
    alias Vxpipe.Gateway.Media.OutputArbiter

    assert_receive {:native_gate_waiting, ^gate}, 1_000
    assert {:ok, resource, _status} = OutputArbiter.readiness(output)

    collector =
      start_supervised!(
        {Collector,
         owner: self(),
         incarnation_id: "native-recovery-clear",
         attempt_id: "native-recovery-clear",
         resources: [resource],
         deadline_ms: System.monotonic_time(:millisecond) + 500},
        id: :recovery_output_readiness
      )

    assert_receive {:vxpipe_readiness_changed, ^collector, %{status: :ready}}, 500
    stop_supervised!(:recovery_output_readiness)
    assert {:ok, _discarded} = OutputSink.clear(output)

    assert {:ok, %{native: native, status: :ready}} =
             GenServer.call(output, {:readiness_binding, :private})

    owner = self()
    token = make_ref()

    assert :ok =
             :sys.install(
               native,
               {token,
                fn state, event, _process ->
                  case {state, event} do
                    {nil, {:in, {:"$gen_call", {caller, _}, :readiness}}} ->
                      send(owner, {:recovery_native_readiness, token, caller})

                      receive do
                        {:continue_recovery_readiness, ^token} -> :clearing
                      after
                        1_000 -> :done
                      end

                    {:clearing, {:in, {:"$gen_call", _from, :vxpipe_audio_output_clear}}} ->
                      send(owner, {:recovery_native_clear, token})

                      receive do
                        {:continue_recovery_clear, ^token} -> :done
                      after
                        1_000 -> :done
                      end

                    _other ->
                      state
                  end
                end, nil}
             )

    try do
      send(connection, {:continue_native_gate, gate})
      assert_receive {:recovery_native_readiness, ^token, reader}, 1_000

      assert :ok =
               :sys.install(
                 output,
                 {token,
                  fn state, event, _process ->
                    case event do
                      {:out, {:ok, %{status: :preparing}}, {^reader, _tag}, _state} ->
                        send(owner, {:recovery_output_rechecked, token})
                        state

                      _other ->
                        state
                    end
                  end, nil}
               )

      clear = :gen_server.send_request(output, :vxpipe_audio_output_clear)
      _ = :sys.get_state(output)
      send(native, {:continue_recovery_readiness, token})
      assert_receive {:recovery_native_clear, ^token}, 1_000
      assert_receive {:recovery_output_rechecked, ^token}, 1_000
      send(native, {:continue_recovery_clear, token})
      assert {:reply, {:ok, _discarded}} = :gen_server.wait_response(clear, 1_000)
    after
      send(native, {:continue_recovery_readiness, token})
      send(native, {:continue_recovery_clear, token})
    end
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

  defp assert_initial_opening_greeting(client, voice) do
    assert %{"type" => "bot-ready"} = await_sideband(client, "bot-ready", 2_000)
    assert_receive {:test_tts_control, ^voice, speak}, 2_000
    assert JSON.decode!(speak) == %{"type" => "Speak", "text" => "Reception is ready."}
    assert_receive {:test_tts_control, ^voice, _flush}, 2_000

    assert %{"data" => %{"text" => "Reception is ready."}} =
             await_sideband(client, "bot-output", 2_000)

    deliver_voice_tone(voice, "greeting-after-opening", 1_500)
    assert :ok = await_tone(client, 1_500, 2_000)

    assert %{"type" => "bot-stopped-speaking"} =
             await_sideband(client, "bot-stopped-speaking", 2_000)

    refute_tone(client, 250, 100)
    assert :ok = send_client_ready(client)
    assert %{"type" => "bot-ready"} = await_sideband(client, "bot-ready", 2_000)
    refute_receive {:test_tts_control, ^voice, _duplicate_greeting}, 100
    assert :ok = send_rtvi_text(client, "first-post-startup-turn")
    assert_receive {:test_agent_runtime_stream, _provider, request}, 2_000
    contents = Enum.map(request.messages, & &1.content)
    assert "Reception is ready." in contents
    refute "Opening notice." in contents
    refute Enum.any?(contents, &String.contains?(&1, "initial-notice.wav"))
  end

  defp startup_wait_configuration(:custom_url) do
    {sounds, options} = wait_configuration(:custom_url)
    {%{call_setup: sounds.transfer_to_human}, options}
  end

  defp startup_wait_configuration(:silent_caller), do: {%{call_setup: nil}, []}
  defp startup_wait_configuration(mode), do: wait_configuration(mode)

  defp agent_wait_configuration(:custom_url) do
    {sounds, options} = wait_configuration(:custom_url)
    {%{transfer_to_agent: sounds.transfer_to_human}, options}
  end

  defp agent_wait_configuration(:silent_caller), do: {%{transfer_to_agent: nil}, []}
  defp agent_wait_configuration(mode), do: wait_configuration(mode)

  defp await_agent_greeting_end(connection, deadline) do
    client = connection.client
    channel = connection.channel_ref

    receive do
      {:ex_webrtc, ^client, {:data, ^channel, payload}} ->
        message = JSON.decode!(payload)

        refute match?(
                 %{
                   "type" => "server-message",
                   "data" => %{"t" => "vxpipe.transfer", "d" => %{"phase" => "completed"}}
                 },
                 message
               ),
               "duplicate transfer completion"

        if message["type"] != "bot-stopped-speaking",
          do: await_agent_greeting_end(connection, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("missing greeting completion")
    end
  end

  defp pause_tool_readiness(tools) do
    owner = self()
    token = make_ref()

    assert :ok =
             :sys.install(
               tools,
               {token,
                fn
                  :waiting, {:in, {:"$gen_call", _from, :readiness}}, _process ->
                    send(owner, {:tool_readiness_waiting, token})

                    receive do
                      {:continue_tool_readiness, ^token} -> :ok
                    after
                      1_000 -> :ok
                    end

                    :done

                  state, _event, _process ->
                    state
                end, :waiting}
             )

    token
  end

  defp assert_startup_wait(client, mode) do
    case mode do
      mode when mode in [:silent_caller, :silent_all] -> refute_audio(client, 150)
      :custom_url -> assert :ok = await_tone(client, 250, 2_000)
      :defaults -> assert client |> await_audio(2_000) |> decodable_pcm_size() == 1_920
    end
  end

  defp deliver_voice_tone(voice, id, frequency) do
    TestTextToSpeechTransport.deliver_control(
      voice,
      JSON.encode!(%{type: "SpeechStarted", speech_id: id})
    )

    <<_header::binary-size(44), pcm::binary>> = tone_wave(frequency)
    TestTextToSpeechTransport.deliver_audio(voice, pcm)

    TestTextToSpeechTransport.deliver_control(
      voice,
      JSON.encode!(%{type: "SpeechMetadata", speech_id: id})
    )
  end

  defp wait_configuration(:defaults), do: {%{}, []}
  defp wait_configuration(:silent_caller), do: {%{transfer_to_human: nil}, []}
  defp wait_configuration(:silent_all), do: {nil, []}

  defp wait_configuration(:live_url) do
    cache =
      start_supervised!(
        {CallEngine.OpeningAudio.AssetCache, maximum_entries: 8, maximum_bytes: 8_388_608}
      )

    # The public HTTP fixture returns a synthetic 4 ms loop as an actual WAV download.
    # Keep the production fetcher, DNS/address policy, TLS and decoder in this lane.
    body = tone_wave(250, 192) |> Base.encode64() |> URI.encode_www_form()
    url = "https://httpbun.com/mix/h=content-type:audio%2Fwav/b64=" <> body

    {%{transfer_to_human: url, transfer_joining: url},
     [wait_sound_settings: [cache: cache, fetcher: {CallEngine.OpeningAudio.ReqFetcher, []}]]}
  end

  defp wait_configuration(:custom_url), do: custom_wait_configuration(9_600)

  defp custom_wait_configuration(sample_count) do
    cache =
      start_supervised!(
        {CallEngine.OpeningAudio.AssetCache, maximum_entries: 8, maximum_bytes: 8_388_608}
      )

    wave = tone_wave(250, sample_count)
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

  defp tone_wave(frequency, sample_count \\ 9_600) do
    pcm =
      for sample <- 0..(sample_count - 1), into: <<>> do
        amplitude = round(12_000 * :math.sin(2 * :math.pi() * frequency * sample / 48_000))
        <<amplitude::little-signed-16>>
      end

    format =
      <<1::little-16, 1::little-16, 48_000::little-32, 96_000::little-32, 2::little-16,
        16::little-16>>

    body = "fmt " <> <<16::little-32>> <> format <> "data" <> <<byte_size(pcm)::little-32>> <> pcm
    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
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
                 opening_audio: Keyword.get(options, :opening_audio),
                 transfer_policy: %{
                   attempt_timeout_ms: Keyword.get(options, :transfer_timeout_ms, 30_000)
                 },
                 participants:
                   Map.merge(
                     %{
                       "caller" => %{
                         type: "human",
                         capabilities:
                           if(
                             Keyword.get(options, :morse, false) or
                               Keyword.get(options, :caller_speech_to_text?, false),
                             do: %{speech_to_text: "test-stt"},
                             else: %{}
                           ),
                         connection: %{
                           service: "web",
                           mode: "receive",
                           admission: "start_call"
                         }
                       },
                       "reception" => %{
                         type: "agent",
                         prompt: "Route callers safely.",
                         first_message:
                           Keyword.get(options, :reception_first_message, %{
                             mode: "wait_for_input"
                           }),
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
                         tools: Keyword.get(options, :billing_tools, %{}),
                         transfer_history:
                           Keyword.get(options, :billing_history, %{mode: "fresh"}),
                         capabilities: %{
                           model_inference: "billing-model",
                           text_to_speech: "test-voice"
                         },
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
                         transfer_notice:
                           Keyword.get(options, :transfer_notice, "This call is recorded.")
                       },
                       "observer" => %{
                         type: "human",
                         connection: %{service: "web", mode: "receive", admission: "start_call"},
                         capabilities:
                           if(Keyword.get(options, :observer_speech_to_text?, false),
                             do: %{speech_to_text: "test-stt"},
                             else: %{}
                           ),
                         while_present:
                           Keyword.get(options, :observer_policy, %{save_transcripts: false})
                       },
                       "recording-restriction" => %{
                         type: "human",
                         connection: %{service: "web", mode: "receive", admission: "start_call"},
                         capabilities: %{},
                         while_present:
                           Keyword.get(options, :restriction_policy, %{record_audio: false})
                       }
                     },
                     Keyword.get(options, :extra_participants, %{})
                   ),
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
               tenant_id: Keyword.get(options, :tenant_id, unique_id("tenant-human-transfer")),
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
                   options: %{model: Keyword.get(options, :reception_model, "test:scripted")}
                 },
                 "billing-model" => %{
                   kind: :model_inference,
                   provider: :req_llm,
                   options: %{model: Keyword.get(options, :billing_model, "test:scripted")}
                 },
                 "test-stt" => %{
                   kind: :speech_to_text,
                   provider: if(Keyword.get(options, :morse), do: MorseCodeSTT, else: Flux),
                   options:
                     if(Keyword.get(options, :morse),
                       do: @morse_options |> Map.new() |> Map.put(:sample_rate, 16_000),
                       else: %{model: "flux-general-en", encoding: :opus, sample_rate: 48_000}
                     )
                 },
                 "test-voice" => %{
                   kind: :text_to_speech,
                   provider:
                     if(Keyword.get(options, :morse), do: MorseCodeTTS, else: FluxTextToSpeech),
                   options:
                     if(Keyword.get(options, :morse),
                       do: Map.new(@morse_options),
                       else: %{
                         model: "flux-test-voice",
                         encoding: :linear16,
                         sample_rate: 48_000
                       }
                     )
                 }
               },
               host_tools: %{"test_agent_tool" => CallEngine.TestAgentTool},
               mcp_integrations: Keyword.get(options, :mcp_integrations)
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

  defp connect(session_id, channel_label, ready? \\ true, direction \\ :sendrecv) do
    client_id = unique_id("client")
    child_spec = Supervisor.child_spec({PeerConnection, []}, id: {PeerConnection, client_id})
    client = start_supervised!(child_spec)
    :ok = PeerConnection.controlling_process(client, self())

    channel_ref = create_channel(client, channel_label)
    input_track = MediaStreamTrack.new(:audio)

    assert {:ok, _transceiver} =
             PeerConnection.add_transceiver(client, input_track, direction: direction)

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

    connection = %{
      client: client,
      channel_ref: channel_ref,
      connection_id: connection_id,
      input_track_id: input_track.id,
      output_track_id: output_track.id
    }

    if ready? and channel_label == "chat", do: await_call_ready(connection), else: connection
  end

  defp join_native_listener(plan, room, key, role) do
    participant = Map.fetch!(plan.participants, key)

    assert {:ok, command} =
             CallEngine.Command.JoinParticipant.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               participant_id: participant.participant_id,
               role: role,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _participant} = CallEngine.join_participant(command)
    direction = if role == :monitor, do: :recvonly, else: :sendrecv

    plan
    |> issue_session(room, participant.participant_id)
    |> then(&connect(&1.session_id, "chat", false, direction))
  end

  defp pause_wait_at(player, frame_count) do
    token = make_ref()
    target = ":#{frame_count - 2}"

    assert :ok =
             :sys.install(player, {token,
              fn
                :done, _event, _process ->
                  :done

                state,
                {:in, {:vxpipe_audio_playback, _sink, correlation, {:completed, _}}},
                _process ->
                  if String.ends_with?(correlation, target) do
                    # The next frame is submitted by handle_continue before this cast.
                    # Pause then drains exactly that frame through the native output.
                    CallEngine.WaitSounds.Player.pause(self())
                    :done
                  else
                    state
                  end

                state, _event, _process ->
                  state
              end, nil})
  end

  defp await_paused_cursor(player, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await_paused_cursor_at(player, deadline)
  end

  defp await_paused_cursor_at(player, deadline) do
    case :sys.get_state(player) do
      %{mode: :paused, offset: offset} ->
        offset

      _playing ->
        assert System.monotonic_time(:millisecond) < deadline, "wait cursor did not pause"

        receive do
        after
          10 -> await_paused_cursor_at(player, deadline)
        end
    end
  end

  defp wait_players(incarnation) do
    [{supervisor, _}] =
      Registry.lookup(CallEngine.RoomRegistry, {:capability_supervisor, incarnation})

    for {_, player, _, [CallEngine.WaitSounds.Player]} <-
          DynamicSupervisor.which_children(supervisor),
        state = :sys.get_state(player),
        state.loop,
        into: %{},
        do: {state.participant_id, {player, state}}
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

  defp send_client_ready(connection) do
    PeerConnection.send_data(
      connection.client,
      connection.channel_ref,
      JSON.encode!(%{
        id: "setup-ready",
        label: "rtvi-ai",
        type: "client-ready",
        data: %{version: "2.1.0"}
      })
    )
  end

  defp await_call_ready(connection) do
    assert :ok = send_client_ready(connection)
    assert %{"type" => "bot-ready"} = await_sideband(connection, "bot-ready", 2_000)
    drain_audio(connection)
    connection
  end

  defp send_rtvi_text(
         connection,
         id \\ unique_id("turn"),
         audio_response \\ false,
         content \\ "Please connect me to human support."
       ) do
    PeerConnection.send_data(
      connection.client,
      connection.channel_ref,
      JSON.encode!(%{
        "id" => id,
        "label" => "rtvi-ai",
        "type" => "send-text",
        "data" => %{
          "content" => content,
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

  defp send_morse(connection, text) do
    assert {:ok, config} = MorseCodeSTT.new(@morse_options)
    assert {:ok, pcm} = MorseEncoder.encode(config, text)
    pcm = pcm <> :binary.copy(<<0, 0>>, 2_880)

    encoder =
      Map.get_lazy(connection, :morse_encoder, fn ->
        Encoder.Native.create(48_000, 1, @application_voip, @automatic_bitrate, @signal_voice)
      end)

    first_sequence = Map.get(connection, :morse_sequence, 1)

    started_at = System.monotonic_time(:millisecond)
    timestamp = started_at * 48

    for {frame, index} <- Enum.with_index(for <<frame::binary-size(1_920) <- pcm>>, do: frame) do
      # Pace actual media at 20 ms per packet; bursting an utterance exceeds the normal ingress bound.
      receive do
      after
        max(started_at + index * 20 - System.monotonic_time(:millisecond), 0) -> :ok
      end

      assert {:ok, payload} = Encoder.Native.encode_packet(encoder, frame, 960)

      packet =
        Packet.new(payload,
          payload_type: 111,
          sequence_number: first_sequence + index,
          timestamp: Integer.mod(timestamp + index * 960, 4_294_967_296),
          ssrc: 123
        )

      assert :ok = PeerConnection.send_rtp(connection.client, connection.input_track_id, packet)
    end

    connection
    |> Map.put(:morse_encoder, encoder)
    |> Map.put(:morse_sequence, first_sequence + div(byte_size(pcm), 1_920))
  end

  defp assert_transcript(connection, participant_id, text) do
    assert_transcript(
      connection,
      participant_id,
      text,
      System.monotonic_time(:millisecond) + 5_000
    )
  end

  defp assert_transcript(connection, participant_id, text, deadline) do
    message =
      await_sideband(
        connection,
        "user-transcription",
        max(deadline - System.monotonic_time(:millisecond), 0)
      )

    case message do
      %{"data" => %{"user_id" => ^participant_id, "text" => ^text, "final" => true}} -> :ok
      _ -> assert_transcript(connection, participant_id, text, deadline)
    end
  end

  defp assert_morse(connection, expected) do
    assert {:ok, config} = MorseCodeTTS.new(@morse_options)
    assert {:ok, morse} = MorseDecoder.new(config)

    assert_morse(
      connection,
      expected,
      connection.morse_opus,
      morse,
      System.monotonic_time(:millisecond) + 5_000
    )
  end

  defp assert_morse(connection, expected, opus, morse, deadline) do
    client = connection.client
    track = connection.output_track_id
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ex_webrtc, ^client, {:rtp, ^track, _rid, packet}} ->
        pcm = Decoder.Native.decode_packet(opus, packet.payload)

        case MorseDecoder.push(morse, pcm) do
          {:ok, next, events} ->
            if {:final, expected} in events do
              :ok
            else
              assert_morse(connection, expected, opus, next, deadline)
            end

          {:error, :unsupported_frequency} when not morse.started? ->
            assert_morse(connection, expected, opus, morse, deadline)

          error ->
            flunk(
              "Morse audio decode failed: #{inspect({error, morse.text, morse.marks, morse.current_kind, morse.current_windows})}"
            )
        end
    after
      remaining ->
        assert {:ok, _decoder, [{:final, ^expected}]} = MorseDecoder.flush(morse)
    end
  end

  defp drain_audio(connection) do
    client = connection.client
    track = connection.output_track_id

    receive do
      {:ex_webrtc, ^client, {:rtp, ^track, _rid, packet}} ->
        # Consume the verified cue's queued tail while retaining the Opus decoder history.
        if decoder = Map.get(connection, :morse_opus),
          do: Decoder.Native.decode_packet(decoder, packet.payload)

        drain_audio(connection)
    after
      0 -> :ok
    end
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
    decoder = Map.get_lazy(connection, :morse_opus, fn -> Decoder.Native.create(48_000, 1) end)
    receive_tone(connection, decoder, frequency, System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp assert_private_transfer_history(request) do
    contents = Enum.map(request.messages, & &1.content)
    assert "Please connect me to human support." in contents

    for private <- ["Private desk notice:", "Held input marker.", "handoff.wav"] do
      refute Enum.any?(contents, &String.contains?(&1, private)),
             "private transfer content entered model history"
    end
  end

  defp assert_handoff_audio_order(connection, conversation_frequency, wait_frequency) do
    receive_handoff_audio(
      connection,
      Decoder.Native.create(48_000, 1),
      {conversation_frequency, wait_frequency},
      :waiting,
      System.monotonic_time(:millisecond) + 5_000
    )
  end

  defp receive_handoff_audio(connection, decoder, frequencies, phase, deadline) do
    client = connection.client
    track = connection.output_track_id
    {conversation_frequency, wait_frequency} = frequencies

    receive do
      {:ex_webrtc, ^client, {:rtp, ^track, _rid, %Packet{} = packet}} ->
        pcm = Decoder.Native.decode_packet(decoder, packet.payload)

        next_phase =
          cond do
            tone?(pcm, 1_000) ->
              refute phase == :conversation, "cue audio followed conversation"
              :cue

            tone?(pcm, conversation_frequency) ->
              refute phase == :waiting, "conversation arrived before the connection cue"
              :conversation

            wait_frequency != nil and tone?(pcm, wait_frequency) ->
              assert phase == :waiting, "wait audio followed the connection cue"
              phase

            true ->
              phase
          end

        deadline =
          if next_phase == :conversation and phase != :conversation,
            do: System.monotonic_time(:millisecond) + 250,
            else: deadline

        receive_handoff_audio(connection, decoder, frequencies, next_phase, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        assert phase == :conversation,
               "missing ordered cue/conversation audio: last phase #{phase}, expected #{conversation_frequency} Hz"
    end
  end

  defp receive_tone(connection, decoder, frequency, deadline) do
    client = connection.client
    track = connection.output_track_id

    packet =
      receive do
        {:ex_webrtc, ^client, {:rtp, ^track, _rid, %Packet{} = packet}} -> packet
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("timed out waiting for #{frequency} Hz audio on #{connection.connection_id}")
      end

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
