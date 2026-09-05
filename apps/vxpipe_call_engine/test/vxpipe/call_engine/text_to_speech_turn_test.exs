defmodule Vxpipe.CallEngine.TextToSpeechTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechProgressed,
    AgentSpeechStarted,
    AgentTurnCompleted,
    AgentTurnInterrupted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
  alias Vxpipe.CallEngine.TestAudioOutputSink
  alias Vxpipe.CallEngine.TestTextToSpeechTransport

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "runtime-secret",
        model: "flux-haley-en",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {TestTextToSpeechTransport, [observer: self()]},
      maximum_requests: 2
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :text_to_speech, text_to_speech)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "routes agent text to PCM and sequences speaking events around sink playout" do
    sink = start_supervised!({TestAudioOutputSink, observer: self()})
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
    assert_receive {:test_tts_transport_started, transport, _connection}

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
               connection_id: "conn-tts",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(attach, sink)

    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-tts",
               correlation_id: "client-turn-1",
               content: "hello",
               audio_response: true,
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 3,
                      text: "Echo: hello",
                      will_be_spoken: true
                    }}

    refute_receive {:vxpipe_event, %AgentTurnCompleted{}}

    assert_receive {:test_tts_control, ^transport, speak}
    assert JSON.decode!(speak)["text"] == "Echo: hello"
    assert_receive {:test_tts_control, ^transport, _flush}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_one"})
    )

    TestTextToSpeechTransport.deliver_audio(transport, <<1, 0, 2, 0>>)

    assert_receive {:test_audio_output, ^sink,
                    %AudioOutputFrame{connection_id: "conn-tts", payload: <<1, 0, 2, 0>>}}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechMetadata","request_id":"req","speech_id":"dg_sp_one"})
    )

    assert_receive {:test_audio_output_finish, ^sink, "client-turn-1"}
    refute_receive {:vxpipe_event, %AgentTurnCompleted{}}

    :ok = TestAudioOutputSink.playback_started(sink)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{sequence: 4}}

    :ok = TestAudioOutputSink.playback_progress(sink, 20, 100)

    assert_receive {:vxpipe_event,
                    %AgentSpeechProgressed{sequence: 5, played_ms: 20, total_ms: 100}}

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 6}}
  end

  test "attributes an immediate typed interruption from another participant and replaces speech" do
    first_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :first_audio_output_sink)

    second_sink =
      start_supervised!({TestAudioOutputSink, observer: self()}, id: :second_audio_output_sink)

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
    assert_receive {:test_tts_transport_started, transport, _connection}

    {first_participant, "conn-first"} = join_and_attach(room, "conn-first", first_sink)
    {second_participant, "conn-second"} = join_and_attach(room, "conn-second", second_sink)

    first =
      send_command(
        room,
        first_participant,
        "conn-first",
        "turn-first",
        "a long first answer"
      )

    assert :ok = CallEngine.send_text(first)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:vxpipe_event,
                    %TextOutput{sequence: 3, correlation_id: "turn-first", text: first_text}}

    assert_receive {:test_tts_control, ^transport, first_speak}
    assert JSON.decode!(first_speak) == %{"type" => "Speak", "text" => first_text}
    assert_receive {:test_tts_control, ^transport, _first_flush}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechStarted","request_id":"req","speech_id":"dg_sp_first"})
    )

    TestTextToSpeechTransport.deliver_audio(transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^first_sink, %AudioOutputFrame{}}
    :ok = TestAudioOutputSink.playback_started(first_sink)
    assert_receive {:vxpipe_event, %AgentSpeechStarted{sequence: 4}}
    :ok = TestAudioOutputSink.playback_progress(first_sink, 20, 100)
    assert_receive {:vxpipe_event, %AgentSpeechProgressed{sequence: 5}}

    interruption =
      send_command(
        room,
        second_participant,
        "conn-second",
        "turn-interrupter",
        "change the subject"
      )

    assert :ok = CallEngine.send_text(interruption)
    assert_receive {:test_audio_output_interrupt, ^first_sink, "turn-first", 20}
    assert_receive {:test_tts_control, ^transport, interrupt_control}

    assert %{
             "type" => "Interrupt",
             "playback_offset" => %{"type" => "time_ms", "value" => 20}
           } = JSON.decode!(interrupt_control)

    assert_receive {:vxpipe_event,
                    %AgentTurnInterrupted{
                      sequence: 6,
                      participant_id: agent_participant_id,
                      source_participant_id: first_participant_id,
                      connection_id: "conn-first",
                      command_id: first_command_id,
                      correlation_id: "turn-first",
                      interrupted_by_participant_id: second_participant_id,
                      interrupted_by_connection_id: "conn-second",
                      interruption_command_id: interruption_command_id,
                      interruption_correlation_id: "turn-interrupter",
                      played_ms: 20
                    }}

    assert agent_participant_id == create.agent_participant_id
    assert first_participant_id == first_participant.participant_id
    assert first_command_id == first.id
    assert second_participant_id == second_participant.participant_id
    assert interruption_command_id == interruption.id

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{sequence: 7, participant_id: ^second_participant_id}}

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{sequence: 8, participant_id: ^second_participant_id}}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 9,
                      connection_id: "conn-second",
                      correlation_id: "turn-interrupter",
                      text: replacement_text
                    }}

    refute_receive {:test_tts_control, ^transport, _replacement_before_ack}

    TestTextToSpeechTransport.deliver_audio(transport, <<3, 0, 4, 0>>)
    refute_receive {:test_audio_output, ^first_sink, %AudioOutputFrame{payload: <<3, 0, 4, 0>>}}

    TestTextToSpeechTransport.deliver_control(
      transport,
      ~s({"type":"SpeechInterrupted","request_id":"req","audio_played_ms":20,"text_spoken":"Echo:","text_remaining":" a long first answer","metadata":{"speech_id":"dg_sp_first"}})
    )

    assert_receive {:test_tts_control, ^transport, replacement_speak}
    assert JSON.decode!(replacement_speak) == %{"type" => "Speak", "text" => replacement_text}
    assert_receive {:test_tts_control, ^transport, _replacement_flush}
  end

  defp join_and_attach(room, connection_id, sink) do
    assert {:ok, join} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, participant} = CallEngine.join_participant(join)

    assert {:ok, attach} =
             AttachConnection.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(attach, sink)
    {participant, connection_id}
  end

  defp send_command(room, participant, connection_id, correlation_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: connection_id,
               correlation_id: correlation_id,
               content: content,
               run_immediately: true,
               audio_response: true,
               deadline: future_deadline()
             )

    command
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
