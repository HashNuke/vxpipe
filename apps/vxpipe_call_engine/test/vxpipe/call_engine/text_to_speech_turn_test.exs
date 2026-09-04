defmodule Vxpipe.CallEngine.TextToSpeechTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentSpeechStarted,
    AgentTurnCompleted,
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

    :ok = TestAudioOutputSink.playback_completed(sink)
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 5}}
  end

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
end
