defmodule Vxpipe.CallEngine.OpeningAudioRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    Error,
    RoomAuthority,
    TestAgentRuntimeModelProvider,
    TestAudioOutputSink,
    TestSpeechToTextTransport,
    TestTextToSpeechTransport
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.CallDefinition.OpeningAudio, as: OpeningSource
  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, TextOutput}
  alias Vxpipe.AgentRuntime.ModelResponse

  test "admits no caller input until configured text finishes actual playout" do
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening")

    assert {:ok, attachment} = CallEngine.attach_connection(command, sink)
    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    assert_receive {:test_tts_control, ^tts_transport, speak}
    assert JSON.decode!(speak) == %{"text" => "This call may be recorded.", "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    assert {:error, %Error{code: :opening_audio_in_progress}} =
             CallEngine.send_text(send_command(plan, room, caller, "conn-opening", "Too early"))

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

    assert :ok = CallEngine.push_audio(attachment, audio_frame(plan, room, caller, 2))
    assert_receive {:test_stt_audio, ^stt_transport, <<2>>}

    assert :ok =
             CallEngine.send_text(send_command(plan, room, caller, "conn-opening", "Now ready"))
  end

  test "ends the room when required opening speech fails" do
    configure_speech_runtime()
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-opening-failure")

    assert {:ok, attachment} = CallEngine.attach_connection(command, sink)
    assert_receive {:test_tts_control, ^tts_transport, _speak}
    assert_receive {:test_tts_control, ^tts_transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"Error","request_id":"req","code":"MESSAGE_INVALID"})
    )

    assert_receive {:DOWN, room_monitor, :process, _room_authority, :opening_audio_unavailable}
    assert room_monitor == attachment.room_monitor
  end

  test "rejects unsupported opening playback before registering a room" do
    configure_speech_runtime()
    plan = compile_plan()

    file_plan = %{
      plan
      | opening_audio: %OpeningSource{
          type: :file_url,
          text: nil,
          url: "https://assets.example.test/opening.wav"
        }
    }

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{"path" => ["opening_audio", "type"]}
            }} = CallEngine.start_call(file_plan)

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {file_plan.tenant_id, file_plan.room_id}
           ) == []

    receiver = Map.fetch!(plan.participants, plan.entry_receiver)
    capabilities = %{receiver.capabilities | text_to_speech: nil}
    receiver = %{receiver | capabilities: capabilities}
    participants = Map.put(plan.participants, plan.entry_receiver, receiver)
    no_tts_plan = %{plan | participants: participants}

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{"path" => ["opening_audio"]}
            }} = CallEngine.start_call(no_tts_plan)

    assert Registry.lookup(
             Vxpipe.CallEngine.RoomRegistry,
             {no_tts_plan.tenant_id, no_tts_plan.room_id}
           ) == []
  end

  test "emits one fixed greeting after opening playout and retains it as assistant history" do
    configure_speech_runtime()
    configure_agent_runtime_provider()
    plan = compile_plan(first_message: %{mode: "fixed", text: "Welcome."})
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-fixed-greeting")
    assert {:ok, _attachment} = CallEngine.attach_connection(command, sink)
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
    assert_receive {:test_tts_control, ^tts_transport, greeting_speak}
    assert JSON.decode!(greeting_speak) == %{"text" => "Welcome.", "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, _greeting_flush}
    complete_speech(tts_transport, sink, "fixed-greeting")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{}}

    assert :ok =
             CallEngine.send_text(
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
    plan = compile_plan(opening_audio: nil, first_message: %{mode: "generated"})
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} = CallEngine.start_call(plan)
    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    refute_receive {:test_agent_runtime_stream, _provider, _request}

    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    command = attach_command(plan, room, caller, "conn-generated-greeting")
    assert {:ok, _attachment} = CallEngine.attach_connection(command, sink)
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
    definition_input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      opening_audio:
        Keyword.get(options, :opening_audio, %{
          type: "text",
          text: "This call may be recorded."
        }),
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{speech_to_text: "plan-stt"}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Answer clearly.",
          first_message: Keyword.get(options, :first_message, %{mode: "wait_for_input"}),
          capabilities: %{model_inference: "test-model", text_to_speech: "plan-tts"},
          tools: %{},
          transfers: []
        }
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
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
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

  defp audio_frame(plan, room, caller, sequence_number) do
    %AudioFrame{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: caller.participant_id,
      connection_id: "conn-opening",
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

  defp assert_eventually_open(plan, attempts \\ 20)

  defp assert_eventually_open(_plan, 0), do: flunk("opening audio did not release input")

  defp assert_eventually_open(plan, attempts) do
    if RoomAuthority.input_admission(plan.tenant_id, plan.room_id) == :open do
      :ok
    else
      receive do
      after
        5 -> assert_eventually_open(plan, attempts - 1)
      end
    end
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

  defp configure_speech_runtime do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    speech_to_text = [
      enabled: true,
      provider: Flux,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      ],
      transport: {TestSpeechToTextTransport, [observer: self()]},
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
      transport: {TestTextToSpeechTransport, [observer: self()]},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      original
      |> Keyword.put(:speech_to_text, speech_to_text)
      |> Keyword.put(:text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)
  end

  defp configure_agent_runtime_provider do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
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

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
