defmodule Vxpipe.CallEngine.SpokenBargeInTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnInterrupted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Provider.Deepgram.{Flux, FluxTextToSpeech}
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TestSpeechToTextTransport
  alias Vxpipe.CallEngine.TestTextToSpeechTransport

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    settings =
      original
      |> Keyword.put(:speech_to_text, speech_to_text_settings(self()))
      |> Keyword.put(:text_to_speech, text_to_speech_settings(self()))

    Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, settings)

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "provider speech start interrupts active agent playout before turn commit" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    {room, participant, _attachment} = create_attached_room(sink)

    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    first = text_command(room, participant, "turn-first", "give me a long answer")
    assert :ok = CallEngine.send_text(first)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 3,
                      correlation_id: "turn-first",
                      text: first_text
                    }}

    assert_receive {:test_tts_control, ^tts_transport, first_speak}
    assert JSON.decode!(first_speak) == %{"type" => "Speak", "text" => first_text}
    assert_receive {:test_tts_control, ^tts_transport, _first_flush}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_first"})
    )

    TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}
    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{sequence: 4}}
    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)
    assert_receive {:vxpipe_event, %AgentSpeechProgressed{sequence: 5}}

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("StartOfTurn", 1, "actually make it shorter")
    )

    assert_receive {:test_audio_output_interrupt, ^sink, "turn-first", 20}
    assert_receive {:test_tts_control, ^tts_transport, interrupt_control}

    assert %{
             "type" => "Interrupt",
             "playback_offset" => %{"type" => "time_ms", "value" => 20}
           } = JSON.decode!(interrupt_control)

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{
                      sequence: 6,
                      correlation_id: "turn-first",
                      interrupted_by_participant_id: participant_id,
                      interrupted_by_connection_id: "conn-audio",
                      interruption_command_id: audio_command_id,
                      interruption_correlation_id: audio_turn_id,
                      played_ms: 20
                    }}

    assert participant_id == participant.participant_id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{
                      sequence: 7,
                      modality: :audio,
                      command_id: ^audio_command_id,
                      correlation_id: ^audio_turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      sequence: 8,
                      text: "actually make it shorter",
                      final: false,
                      command_id: ^audio_command_id,
                      correlation_id: ^audio_turn_id
                    }}

    TestSpeechToTextTransport.deliver(
      stt_transport,
      turn_message("EndOfTurn", 2, "actually make it shorter", "model")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      sequence: 9,
                      final: true,
                      command_id: ^audio_command_id,
                      correlation_id: ^audio_turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{
                      sequence: 10,
                      command_id: ^audio_command_id,
                      correlation_id: ^audio_turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 11,
                      correlation_id: ^audio_turn_id,
                      text: replacement_text
                    }}

    refute_receive {:vxpipe_event, %AgentTurnInterrupted{}}
    refute_receive {:test_tts_control, ^tts_transport, _replacement_before_ack}

    TestTextToSpeechTransport.deliver_control(
      tts_transport,
      ~s({"type":"SpeechInterrupted","request_id":"req","audio_played_ms":20,"text_spoken":"Echo:","text_remaining":" give me a long answer","metadata":{"speech_id":"dg_sp_first"}})
    )

    assert_receive {:test_tts_control, ^tts_transport, replacement_speak}
    assert JSON.decode!(replacement_speak) == %{"type" => "Speak", "text" => replacement_text}
  end

  test "provider speech start while the agent is idle does not emit an interruption" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
    {_room, _participant, _attachment} = create_attached_room(sink)

    assert_receive {:test_tts_transport_started, _tts_transport, _connection}
    assert_receive {:test_stt_transport_started, stt_transport, _connection}

    TestSpeechToTextTransport.deliver(stt_transport, turn_message("StartOfTurn", 1, "hello"))

    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1, modality: :audio}}
    assert_receive {:vxpipe_event, %ParticipantTranscription{sequence: 2, text: "hello"}}
    refute_receive {:vxpipe_event, %AgentTurnInterrupted{}}
  end

  defp create_attached_room(sink) do
    room_id = unique_id("room")

    assert {:ok, create} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               agent: :deterministic_text,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create)

    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, participant} = CallEngine.join_participant(join)

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-audio",
               deadline: future_deadline()
             )

    assert {:ok, attachment} = CallEngine.attach_connection(attach, sink)
    {room, participant, attachment}
  end

  defp text_command(room, participant, correlation_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-audio",
               correlation_id: correlation_id,
               content: content,
               run_immediately: true,
               audio_response: true,
               deadline: future_deadline()
             )

    command
  end

  defp speech_to_text_settings(observer) do
    [
      enabled: true,
      provider: Flux,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-general-en",
        encoding: :opus,
        sample_rate: 48_000
      ],
      transport: {TestSpeechToTextTransport, [observer: observer]},
      media_ingress: [
        maximum_frames: 50,
        maximum_bytes: 262_144,
        maximum_age_ms: 2_000,
        maximum_consecutive_overflows: 5
      ]
    ]
  end

  defp text_to_speech_settings(observer) do
    [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, [observer: observer]},
      maximum_requests: 2
    ]
  end

  defp turn_message(event, sequence, transcript, trigger \\ nil) do
    message = %{
      "type" => "TurnInfo",
      "request_id" => "request-1",
      "sequence_id" => sequence,
      "event" => event,
      "turn_index" => 0,
      "audio_window_start" => 0.0,
      "audio_window_end" => 1.0,
      "transcript" => transcript,
      "words" => [],
      "end_of_turn_confidence" => 0.8
    }

    message = if trigger == nil, do: message, else: Map.put(message, "trigger", trigger)
    JSON.encode!(message)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
