defmodule Vxpipe.CallEngine.AudioTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant}
  alias Vxpipe.CallEngine.ConnectionAttachment

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    ParticipantTranscription,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Media.AudioFrame
  alias Vxpipe.CallEngine.Provider.Deepgram.Flux
  alias Vxpipe.CallEngine.TestSpeechToTextTransport

  setup do
    application_settings =
      Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(application_settings, :speech_to_text, speech_to_text_settings(self()))
    )

    on_exit(fn ->
      Application.put_env(
        :vxpipe_call_engine,
        Vxpipe.CallEngine.Application,
        application_settings
      )
    end)

    :ok
  end

  test "routes one committed Flux turn through the room's deterministic agent" do
    room_id = unique_id("room")

    assert {:ok, create_command} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               agent: :deterministic_text,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create_command)

    assert {:ok, join_command} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, participant} = CallEngine.join_participant(join_command)

    assert {:ok, attach_command} =
             AttachConnection.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-audio",
               deadline: future_deadline()
             )

    assert {:ok,
            %ConnectionAttachment{
              room_monitor: room_monitor,
              media_ingress: media_ingress
            } = attachment} = CallEngine.attach_connection(attach_command)

    assert is_reference(room_monitor)
    assert is_pid(media_ingress)
    assert_receive {:test_stt_transport_started, transport, _connection}

    frame = audio_frame(room, participant, 1, <<1, 2, 3>>)
    assert :ok = CallEngine.push_audio(attachment, frame)
    assert_receive {:test_stt_audio, ^transport, <<1, 2, 3>>}

    TestSpeechToTextTransport.deliver(transport, turn_message("StartOfTurn", 1, "hello"))

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{
                      sequence: 1,
                      modality: :audio,
                      command_id: command_id,
                      correlation_id: turn_id
                    }}

    assert "cmd_" <> _ = command_id
    assert "turn_" <> _ = turn_id

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      sequence: 2,
                      text: "hello",
                      final: false,
                      provider_turn_index: 0,
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("Update", 2, "hello there")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      sequence: 3,
                      text: "hello there",
                      final: false,
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    refute_receive {:vxpipe_event, %TextOutput{}}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("EndOfTurn", 3, "hello there", "model")
    )

    assert_receive {:vxpipe_event,
                    %ParticipantTranscription{
                      sequence: 4,
                      text: "hello there",
                      final: true,
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{
                      sequence: 5,
                      modality: :audio,
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 6,
                      text: "Echo: hello there",
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{
                      sequence: 7,
                      command_id: ^command_id,
                      correlation_id: ^turn_id
                    }}

    TestSpeechToTextTransport.deliver(
      transport,
      turn_message("EndOfTurn", 3, "hello there", "model")
    )

    refute_receive {:vxpipe_event, %TextOutput{}}
    Process.demonitor(room_monitor, [:flush])
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

  defp audio_frame(room, participant, sequence, payload) do
    %AudioFrame{
      tenant_id: "tenant-demo",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: "conn-audio",
      track_id: "track-audio",
      codec: :opus,
      sample_rate: 48_000,
      channels: 1,
      sequence_number: sequence,
      timestamp: sequence * 960,
      payload: payload,
      received_at: System.monotonic_time(:millisecond)
    }
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
