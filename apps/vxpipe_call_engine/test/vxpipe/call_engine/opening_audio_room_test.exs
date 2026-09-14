defmodule Vxpipe.CallEngine.OpeningAudioRoomTest do
  use ExUnit.Case, async: false

  @opening_audio_stop_event [:vxpipe, :call_engine, :opening_audio, :stop]

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    Error,
    RoomAuthority,
    TestAgentRuntimeModelProvider,
    TestAudioOutputSink,
    TestCallLifecycleTimer,
    TestOpeningAudioFetcher,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport,
    TestTransferConnection
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.OpeningAudio.{AssetCache, Download}
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, TextOutput}
  alias Vxpipe.AgentRuntime.ModelResponse

  test "resumes the same wait cursor after opening playback while model setup is pending" do
    configure_speech_runtime()
    configure_agent_runtime_provider(Vxpipe.CallEngine.TestSelectiveAgentRuntimeModelProvider)
    owner = self()

    configure_opening_audio(fn ->
      send(owner, {:opening_fetch_waiting, self()})

      receive do
        :release_notice -> {:ok, %Download{body: wave(<<1, 0, 2, 0>>), content_type: "audio/wav"}}
      end
    end)

    wait_url = "https://assets.example.test/cursor-wait.wav"
    wait_pcm = for value <- 100..500//100, into: <<>>, do: :binary.copy(<<value::little-16>>, 960)

    plan =
      compile_plan(
        model: "test:blocked",
        opening_audio: %{type: "file_url", url: "https://assets.example.test/cursor-notice.wav"},
        wait_sounds: %{call_setup: wait_url}
      )

    assert {:ok, room} =
             CallEngine.start_call(plan,
               wait_sound_settings: [
                 fetcher:
                   {TestOpeningAudioFetcher,
                    observer: self(),
                    response: {:ok, %Download{body: wave(wait_pcm), content_type: "audio/wav"}}}
               ]
             )

    assert_receive {:test_agent_runtime_model_preparing, model_preparer}, 1_000
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening-cursor")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:opening_fetch_waiting, fetcher}, 1_000
    assert_receive {:test_audio_output, ^sink, first}, 1_000
    assert first.payload == :binary.copy(<<100::little-16>>, 960)
    assert_receive {:test_audio_output_finish, ^sink, _}
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:test_audio_output, ^sink, second}
    assert second.payload == :binary.copy(<<200::little-16>>, 960)
    assert_receive {:test_audio_output_finish, ^sink, _}

    send(fetcher, :release_notice)
    refute_receive {:test_audio_output, ^sink, _}, 100
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:test_audio_output, ^sink, notice}
    assert notice.payload == <<1, 0, 2, 0>>
    assert_receive {:test_audio_output_finish, ^sink, _}
    refute_receive {:test_audio_output, ^sink, _}, 100
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:test_audio_output, ^sink, resumed}
    assert resumed.payload == :binary.copy(<<300::little-16>>, 960)
    assert resumed.command_id == first.command_id
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio
    send(model_preparer, :release_test_agent_runtime_model)
  end

  test "plays its own opening voice with a human initial receiver and releases it after playback" do
    configure_speech_runtime()
    plan = compile_plan(receiver: :human)
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    assert receiver.kind == :human
    assert receiver.capabilities.text_to_speech == nil
    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, transport, connection}
    assert URI.decode_query(URI.parse(connection.url).query)["model"] == "flux-opening-voice"
    monitor = Process.monitor(transport)

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    receiver_command = attach_command(plan, room, receiver, "conn-human-receiver")
    assert {:ok, _receiver_attachment} = TestTransferConnection.attach(receiver_command, nil)
    command = attach_command(plan, room, caller, "conn-human-opening")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_tts_control, ^transport, speak}
    assert JSON.decode!(speak)["text"] == "This call may be recorded."
    assert_receive {:test_tts_control, ^transport, _flush}
    complete_speech(transport, sink, "human-opening")
    assert_eventually_open(plan)
    assert_receive {:DOWN, ^monitor, :process, ^transport, _reason}
    refute_receive {:test_agent_runtime_stream, _provider, _request}
  end

  for source <- [:file_url, :text] do
    test "records neither announcement nor live/delayed caller audio during #{source} opening" do
      configure_speech_runtime()

      configure_opening_audio(
        {:ok, %Download{body: wave(<<1, 0, 2, 0>>), content_type: "audio/wav"}}
      )

      clock = :atomics.new(1, [])
      configure_recording_clock(clock)

      opening =
        case unquote(source) do
          :file_url -> %{type: "file_url", url: "https://assets.example.test/notice.wav"}
          :text -> %{type: "text", text: "Notice.", text_to_speech: "opening-tts"}
        end

      plan = compile_plan(opening_audio: opening)

      caller = Map.fetch!(plan.participants, plan.entry_caller)

      assert {:ok, room} =
               CallEngine.start_call(plan,
                 recording: [
                   enabled: true,
                   targets: [:full_mix, :individual_tracks],
                   writer: {Vxpipe.CallEngine.TestRecordingWriter, [observer: self()]},
                   maximum_pull_frames: 8
                 ]
               )

      assert_receive {:test_recording_writer_opened, _caller, recording, %{stream_id: "full-mix"}}
      sink = start_supervised!({TestAudioOutputSink, observer: self()})
      command = attach_command(plan, room, caller, "conn-opening-recording")
      assert {:ok, attachment} = TestTransferConnection.attach(command, sink)

      if unquote(source) == :text do
        assert_receive {:test_tts_transport_started, transport, _connection}
        assert_receive {:test_tts_control, ^transport, _speak}, 1_000
        assert_receive {:test_tts_control, ^transport, _flush}

        TestTextToSpeechTransport.deliver_control(
          transport,
          ~s({"type":"SpeechStarted","request_id":"req","speech_id":"recording-opening"})
        )

        TestTextToSpeechTransport.deliver_audio(transport, <<1, 0, 2, 0>>)

        TestTextToSpeechTransport.deliver_control(
          transport,
          ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"recording-opening"})
        )
      end

      assert_receive {:test_audio_output_finish, ^sink, _request}
      mixer = Vxpipe.CallEngine.RoomMixer.whereis(room.incarnation_id)

      assert :ok = TestAudioOutputSink.playback_started(sink)
      assert :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)

      assert {:ok, handoff} =
               Vxpipe.CallEngine.RoomMixer.open_recording_egress(mixer, command.connection_id)

      assert :ok =
               Vxpipe.CallEngine.Recording.EgressHandoff.offer(
                 handoff,
                 %Vxpipe.CallEngine.Media.EgressAcceptedFrame{
                   tenant_id: plan.tenant_id,
                   room_id: plan.room_id,
                   incarnation_id: room.incarnation_id,
                   source_participant_id: caller.participant_id,
                   connection_id: command.connection_id,
                   sample_rate: 48_000,
                   channels: 1,
                   payload: :binary.copy(<<500::little-signed-16>>, 960)
                 }
               )

      assert :ok = CallEngine.push_room_audio(attachment, recording_frame(plan, room, caller, 0))
      assert {:ok, %{delivered: 0}} = Vxpipe.CallEngine.RoomMixer.flush_through(mixer, 0)
      assert %{accepted_chunks: 0} = Vxpipe.CallEngine.RoomRecording.stats(recording)

      :atomics.put(clock, 1, 40)
      assert :ok = TestAudioOutputSink.playback_completed(sink)
      assert_eventually_open(plan)

      # Decoding may finish after the opening gate changes; its original timestamp is still held.
      assert :ok =
               CallEngine.push_room_audio(attachment, recording_frame(plan, room, caller, 960))

      assert {:ok, %{delivered: 0}} = Vxpipe.CallEngine.RoomMixer.flush_through(mixer, 960)
      assert %{accepted_chunks: 0} = Vxpipe.CallEngine.RoomRecording.stats(recording)

      assert :ok =
               CallEngine.push_room_audio(attachment, recording_frame(plan, room, caller, 1920))

      assert {:ok, %{delivered: 2}} = Vxpipe.CallEngine.RoomMixer.flush_through(mixer, 1920)
      assert_receive {:test_recording_chunk, "full-mix", full_mix}
      assert full_mix.offset_samples == 1920
      assert_receive {:test_recording_chunk, individual_id, individual}
      assert individual_id != "full-mix"
      assert individual.offset_samples == 1920
      assert %{accepted_chunks: 2} = Vxpipe.CallEngine.RoomRecording.stats(recording)
    end
  end

  test "admits no caller input until configured text finishes actual playout" do
    attach_opening_audio_telemetry()
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening")

    assert {:ok, attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    assert_receive {:test_tts_control, ^tts_transport, speak}
    assert JSON.decode!(speak) == %{"text" => "This call may be recorded.", "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    assert {:error, %Error{code: :opening_audio_in_progress}} =
             TestTransferConnection.send_text(
               send_command(plan, room, caller, "conn-opening", "Too early")
             )

    assert :ok = CallEngine.push_audio(attachment, audio_frame(plan, room, caller, 1))
    refute_receive {:test_stt_audio, ^stt_transport, _audio}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"opening"})
    )

    TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"opening"})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn_id}
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio

    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio

    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_eventually_open(plan)

    assert_receive {:opening_audio_telemetry, @opening_audio_stop_event,
                    %{count: 1, duration: duration}, %{outcome: :completed, source: :text}}

    assert duration >= 0

    assert :ok = CallEngine.push_audio(attachment, audio_frame(plan, room, caller, 2))
    assert_receive {:test_stt_audio, ^stt_transport, <<2>>}

    assert :ok =
             TestTransferConnection.send_text(
               send_command(plan, room, caller, "conn-opening", "Now ready")
             )
  end

  test "ends the room when required opening speech fails" do
    attach_opening_audio_telemetry()
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening-failure")

    assert {:ok, attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_tts_control, ^tts_transport, _speak}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"Error","request_id":"req","code":"MESSAGE_INVALID"})
    )

    assert_receive {:DOWN, room_monitor, :process, _room_authority, :opening_audio_unavailable},
                   1_000

    assert room_monitor == attachment.room_monitor

    assert_receive {:opening_audio_telemetry, @opening_audio_stop_event,
                    %{count: 1, duration: duration}, %{outcome: :failed, source: :text}}

    assert duration >= 0
  end

  test "targets the entry caller rather than another attached participant" do
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    receiver_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :receiver_opening_sink)

    receiver_command =
      attach_command(plan, room, receiver, "conn-opening-receiver")

    assert {:ok, _attachment} = TestTransferConnection.attach(receiver_command, receiver_sink)
    refute_receive {:test_tts_control, ^tts_transport, _payload}
    refute_receive {:test_audio_output, ^receiver_sink, _frame}
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio

    caller_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :caller_opening_sink)

    caller_command = attach_command(plan, room, caller, "conn-opening-caller")
    assert {:ok, _attachment} = TestTransferConnection.attach(caller_command, caller_sink)
    assert_receive {:test_tts_control, ^tts_transport, _speak}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    complete_speech(tts_transport, caller_sink, "opening-caller-only")
    refute_receive {:test_audio_output, ^receiver_sink, _frame}
    assert_eventually_open(plan)
  end

  test "reuses bounded rendered text for the same tenant and text-to-speech identity" do
    configure_speech_runtime()
    configure_opening_audio({:error, :unexpected_file_fetch})

    first_plan = compile_plan()
    first_caller = Map.fetch!(first_plan.participants, first_plan.entry_caller)
    assert {:ok, first_room} = CallEngine.start_call(first_plan)
    assert_receive {:test_tts_transport_started, first_tts, _connection}

    first_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :first_text_cache_sink)

    first_command = attach_command(first_plan, first_room, first_caller, "conn-text-cache-first")
    assert {:ok, _attachment} = TestTransferConnection.attach(first_command, first_sink)
    assert_receive {:test_tts_control, ^first_tts, _speak}
    assert_receive {:test_tts_control, ^first_tts, _flush}
    complete_speech(first_tts, first_sink, "text-cache-first")
    assert_eventually_open(first_plan)

    second_plan = compile_plan()
    second_caller = Map.fetch!(second_plan.participants, second_plan.entry_caller)
    assert {:ok, second_room} = CallEngine.start_call(second_plan)
    assert_receive {:test_tts_transport_started, second_tts, _connection}

    second_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :second_text_cache_sink)

    second_command =
      attach_command(second_plan, second_room, second_caller, "conn-text-cache-second")

    assert {:ok, _attachment} = TestTransferConnection.attach(second_command, second_sink)
    assert_receive {:test_audio_output, ^second_sink, frame}
    assert frame.payload == <<1, 0, 2, 0>>
    assert_receive {:test_audio_output_finish, ^second_sink, _correlation_id}
    refute_receive {:test_tts_control, ^second_tts, _payload}

    assert :ok = TestAudioOutputSink.playback_started(second_sink)
    assert :ok = TestAudioOutputSink.playback_completed(second_sink)
    assert_eventually_open(second_plan)

    third_plan = compile_plan(opening_profile: "another-opening-binding")
    third_caller = Map.fetch!(third_plan.participants, third_plan.entry_caller)
    assert {:ok, third_room} = CallEngine.start_call(third_plan)
    assert_receive {:test_tts_transport_started, third_tts, _connection}

    third_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :third_text_cache_sink)

    third_command = attach_command(third_plan, third_room, third_caller, "conn-text-cache-third")
    assert {:ok, _attachment} = TestTransferConnection.attach(third_command, third_sink)
    assert_receive {:test_tts_control, ^third_tts, _speak}
    assert_receive {:test_tts_control, ^third_tts, _flush}
    complete_speech(third_tts, third_sink, "text-cache-third")
    assert_eventually_open(third_plan)
  end

  test "starts caller-idle timing only after opening playout completes" do
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, _maximum_timer, 60_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening-idle")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_stt_transport_started, _stt_transport, _connection}
    refute_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_tts_control, ^tts_transport, _speak}
    assert_receive {:test_tts_control, ^tts_transport, _flush}
    refute_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}

    complete_speech(tts_transport, sink, "opening-idle")
    assert_eventually_open(plan)
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}
    assert_receive {:test_call_lifecycle_timer_scheduled, _idle_timer, 15_000}
  end

  test "plays a file opening through a supervised room worker without text-to-speech" do
    configure_speech_runtime()

    configure_opening_audio(
      {:ok, %Download{body: wave(<<1, 0, 2, 0>>), content_type: "audio/wav"}}
    )

    url = "https://assets.example.test/opening.wav"
    plan = compile_plan(opening_audio: %{type: "file_url", url: url})
    plan = without_receiver_text_to_speech(plan)
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    refute_receive {:test_tts_transport_started, _transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-file-opening")

    assert {:ok, attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_stt_transport_started, stt_transport, _connection}
    assert_receive {:test_opening_audio_fetch, ^url, _limits}

    assert_receive {:test_audio_output, ^sink, frame}
    assert frame.participant_id == caller.participant_id
    assert frame.connection_id == "conn-file-opening"
    assert frame.payload == <<1, 0, 2, 0>>
    assert_receive {:test_audio_output_finish, ^sink, correlation_id}

    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio

    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(plan, room, caller, 1, "conn-file-opening")
             )

    refute_receive {:test_stt_audio, ^stt_transport, _audio}

    assert :ok = TestAudioOutputSink.playback_started(sink)
    assert :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :opening_audio
    assert :ok = TestAudioOutputSink.playback_completed(sink)
    assert_eventually_open(plan)

    assert is_binary(correlation_id)

    assert :ok =
             CallEngine.push_audio(
               attachment,
               audio_frame(plan, room, caller, 2, "conn-file-opening")
             )

    assert_receive {:test_stt_audio, ^stt_transport, <<2>>}
  end

  test "fails startup when required conversational speech fails during a file opening" do
    configure_speech_runtime()
    test = self()

    configure_opening_audio(fn ->
      send(test, {:test_opening_audio_waiting, self()})

      receive do
        :release_opening_audio ->
          {:ok, %Download{body: wave(<<1, 0, 2, 0>>), content_type: "audio/wav"}}
      end
    end)

    plan =
      compile_plan(
        agent_text_to_speech: true,
        opening_audio: %{
          type: "file_url",
          url: "https://assets.example.test/opening-with-tts.wav"
        }
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-file-opening-tts-failure")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    room_monitor = Process.monitor(authority)
    assert_receive {:test_opening_audio_waiting, worker}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"Error","request_id":"req","code":"MESSAGE_INVALID"})
    )

    assert_receive {:DOWN, ^room_monitor, :process, _authority, :startup_unavailable}, 1_000
    refute_receive {:test_call_ready, _room_id}
    send(worker, :release_opening_audio)
  end

  test "ends the room when a required file opening cannot be loaded" do
    configure_speech_runtime()
    test = self()

    configure_opening_audio(fn ->
      send(test, {:test_opening_audio_waiting, self()})

      receive do
        :fail_opening_audio -> {:error, :unavailable}
      end
    end)

    plan =
      compile_plan(
        opening_audio: %{
          type: "file_url",
          url: "https://assets.example.test/missing.wav"
        }
      )
      |> without_receiver_text_to_speech()

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-file-opening-failure")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    [{authority, _}] = Registry.lookup(CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})
    room_monitor = Process.monitor(authority)
    assert_receive {:test_opening_audio_waiting, worker}
    send(worker, :fail_opening_audio)

    assert_receive {:DOWN, ^room_monitor, :process, ^authority, :opening_audio_unavailable},
                   1_000
  end

  test "rejects a missing resolved opening voice without falling back to the agent" do
    configure_speech_runtime()
    plan = compile_plan(agent_text_to_speech: true)
    no_tts_plan = %{plan | opening_audio: %{plan.opening_audio | text_to_speech: nil}}

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{"path" => ["opening_audio", "text_to_speech"]}
            }} = CallEngine.start_call(no_tts_plan)

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {no_tts_plan.tenant_id, no_tts_plan.room_id}
           ) == []
  end

  test "emits one fixed greeting after opening playout and retains it as assistant history" do
    configure_speech_runtime()
    configure_agent_runtime_provider()

    plan =
      compile_plan(agent_text_to_speech: true, first_message: %{mode: "fixed", text: "Welcome."})

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)

    voices =
      for _voice <- 1..2, into: %{} do
        assert_receive {:test_tts_transport_started, transport, connection}
        model = URI.decode_query(URI.parse(connection.url).query)["model"]
        {model, transport}
      end

    agent_tts = Map.fetch!(voices, "flux-plan-voice")
    tts_transport = Map.fetch!(voices, "flux-opening-voice")

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-fixed-greeting")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_stt_transport_started, _stt_transport, _connection}

    assert_receive {:test_tts_control, ^tts_transport, opening_speak}

    assert JSON.decode!(opening_speak) == %{
             "text" => "This call may be recorded.",
             "type" => "Speak"
           }

    assert_receive {:test_tts_control, ^tts_transport, _opening_flush}
    refute_receive {:vxpipe_event, %TextOutput{text: "Welcome."}}

    complete_speech(tts_transport, sink, "opening-fixed")

    assert_receive {:vxpipe_event, %TextOutput{text: "Welcome."}}
    assert_receive {:test_tts_control, ^agent_tts, greeting_speak}
    assert JSON.decode!(greeting_speak) == %{"text" => "Welcome.", "type" => "Speak"}
    assert_receive {:test_tts_control, ^agent_tts, _greeting_flush}
    complete_speech(agent_tts, sink, "fixed-greeting")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}

    assert :ok =
             TestTransferConnection.send_text(
               send_command(plan, room, caller, "conn-fixed-greeting", "Hello")
             )

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert Enum.map(request.messages, &{&1.role, &1.content}) == [
             {:system, "Answer clearly."},
             {:assistant, "Welcome."},
             {:user, "Hello"}
           ]

    assert {:ok, response} = ModelResponse.new(text: "Hello back.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  test "asks the model for a generated greeting only after the caller attaches" do
    configure_speech_runtime()
    configure_agent_runtime_provider()

    plan =
      compile_plan(
        agent_text_to_speech: true,
        opening_audio: nil,
        first_message: %{mode: "generated"}
      )

    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    refute_receive {:test_agent_runtime_stream, _provider, _request}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-generated-greeting")
    assert {:ok, _attachment} = TestTransferConnection.attach(command, sink)
    assert_receive {:test_stt_transport_started, _stt_transport, _connection}

    assert_receive {:test_agent_runtime_stream, provider, request}
    prompt = List.last(request.messages)
    assert prompt.role == :user
    assert prompt.origin == :engine

    assert {:ok, response} = ModelResponse.new(text: "Welcome from the model.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_event, %TextOutput{text: "Welcome from the model."}}
    assert_receive {:test_tts_control, ^tts_transport, greeting_speak}

    assert JSON.decode!(greeting_speak) == %{
             "text" => "Welcome from the model.",
             "type" => "Speak"
           }
  end

  defp compile_plan(options \\ []) do
    opening_profile = Keyword.get(options, :opening_profile, "opening-tts")

    receiver =
      if Keyword.get(options, :receiver) == :human do
        %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        }
      else
        capabilities =
          if Keyword.get(options, :agent_text_to_speech, false),
            do: %{model_inference: "test-model", text_to_speech: "plan-tts"},
            else: %{model_inference: "test-model"}

        %{
          type: "agent",
          prompt: "Answer clearly.",
          first_message: Keyword.get(options, :first_message, %{mode: "wait_for_input"}),
          capabilities: capabilities,
          tools: %{},
          transfers: []
        }
      end

    definition_input = %{
      schema_version: CallDefinition.schema_version(),
      wait_sounds: Keyword.get(options, :wait_sounds),
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio:
        Keyword.get(options, :opening_audio, %{
          type: "text",
          text: "This call may be recorded.",
          text_to_speech: opening_profile
        }),
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{speech_to_text: "plan-stt"}
        },
        "receiver" => receiver
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(definition_input, resource_id: "definition-opening", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "definition-opening", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-opening",
               actor_id: "actor-opening",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        opening_profile => %{
          kind: :text_to_speech,
          provider: FluxTextToSpeech,
          options: %{model: "flux-opening-voice", encoding: :linear16, sample_rate: 48_000}
        },
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: Keyword.get(options, :model, "test:scripted")}
        },
        "plan-stt" => %{
          kind: :speech_to_text,
          provider: Flux,
          options: %{model: "flux-general-multi", encoding: :opus, sample_rate: 48_000}
        },
        "plan-tts" => %{
          kind: :text_to_speech,
          provider: FluxTextToSpeech,
          options: %{model: "flux-plan-voice", encoding: :linear16, sample_rate: 48_000}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp attach_command(plan, room, caller, connection_id) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    command
  end

  defp send_command(plan, room, caller, connection_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               deadline: future_deadline()
             )

    command
  end

  defp audio_frame(plan, room, caller, sequence_number, connection_id \\ "conn-opening") do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: caller.participant_id,
      connection_id: connection_id,
      track_id: "track-opening",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: sequence_number,
      timestamp: sequence_number * 960,
      payload: <<sequence_number>>,
      received_at: System.monotonic_time(:millisecond)
    }
  end

  defp assert_eventually_open(plan) do
    room_id = plan.room_id
    assert_receive {:test_call_ready, ^room_id}, 1_000
    assert RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :open
  end

  defp complete_speech(tts_transport, sink, speech_id) do
    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{"type" => "SpeechStarted", "request_id" => "req", "speech_id" => speech_id})
    )

    TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{
        "type" => "SpeechMetadata",
        "request_id" => "req",
        "speech_id" => speech_id
      })
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn_id}
    :ok = TestAudioOutputSink.playback_started(sink)
    :ok = TestAudioOutputSink.playback_completed(sink)
  end

  defp configure_opening_audio(response) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)
    cache = start_supervised!({AssetCache, maximum_entries: 8, maximum_bytes: 4_194_304})

    opening_audio = [
      cache: cache,
      fetcher: {TestOpeningAudioFetcher, [observer: self(), response: response]},
      maximum_bytes: 256,
      maximum_duration_ms: 1_000,
      timeout_ms: 1_000
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :opening_audio, opening_audio)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp without_receiver_text_to_speech(plan) do
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    capabilities = %{receiver.capabilities | text_to_speech: nil}
    receiver = %{receiver | capabilities: capabilities}
    participants = Map.put(plan.participants, plan.entry_receiver, receiver)
    %{plan | participants: participants}
  end

  defp wave(pcm) do
    format =
      <<1::little-16, 1::little-16, 48_000::little-32, 96_000::little-32, 2::little-16,
        16::little-16>>

    body =
      "fmt " <>
        <<byte_size(format)::little-32>> <>
        format <>
        "data" <>
        <<byte_size(pcm)::little-32>> <> pcm

    "RIFF" <> <<byte_size(body) + 4::little-32>> <> "WAVE" <> body
  end

  defp configure_speech_runtime do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    opening_audio_cache =
      start_supervised!(
        {AssetCache, maximum_entries: 8, maximum_bytes: 4_194_304},
        id: :speech_runtime_opening_audio_cache
      )

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      ],
      transport: {TestSpeechToTextTransport, [observer: self(), ready_on_start: true]},
      media_ingress: [
        maximum_frames: 8,
        maximum_bytes: 1_024,
        maximum_age_ms: 1_000,
        maximum_consecutive_overflows: 2
      ]
    ]

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, [observer: self(), ready_on_start: true]},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.update!(:opening_audio, &Keyword.put(&1, :cache, opening_audio_cache))
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp configure_recording_clock(clock) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    settings =
      Keyword.update!(original, :room_mixer, fn settings ->
        settings
        |> Keyword.delete(:playout_delay_ms)
        |> Keyword.put(:clock_origin_ms, 0)
        |> Keyword.put(:clock, fn -> :atomics.get(clock, 1) end)
      end)

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp recording_frame(plan, room, caller, timestamp) do
    policy =
      room.incarnation_id
      |> Vxpipe.CallEngine.MediaPolicy.Authority.whereis()
      |> Vxpipe.CallEngine.MediaPolicy.Authority.snapshot()

    %Vxpipe.CallEngine.Media.NormalizedFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      source_participant_id: caller.participant_id,
      connection_id: "conn-opening-recording",
      track_id: "embedded",
      sequence_number: div(timestamp, 960),
      timestamp: timestamp,
      policy_revision:
        Vxpipe.CallEngine.MediaPolicy.Snapshot.interval(
          policy,
          :audio_input,
          caller.participant_id
        ),
      sample_rate: 48_000,
      channels: 1,
      payload: :binary.copy(<<1_000::little-signed-16>>, 960)
    }
  end

  defp configure_agent_runtime_provider(provider \\ TestAgentRuntimeModelProvider) do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, provider)
      |> Keyword.put(:model_provider_options, owner: self())

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  def handle_opening_audio_telemetry(event, measurements, metadata, test) do
    send(test, {:opening_audio_telemetry, event, measurements, metadata})
  end

  defp attach_opening_audio_telemetry do
    handler_id = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        @opening_audio_stop_event,
        &__MODULE__.handle_opening_audio_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
