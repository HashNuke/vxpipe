defmodule Vxpipe.CallEngine.ModelInferenceTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    AgentTurnFailed,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.TestModelInferenceProvider

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    model_inference = [
      enabled: true,
      provider: TestModelInferenceProvider,
      provider_options: [observer: self()],
      system_prompt: "Answer as a compact test assistant.",
      maximum_context_turns: 4,
      maximum_pending_requests: 2,
      maximum_output_bytes: 65_536,
      request_timeout_ms: 1_000
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :model_inference, model_inference)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "routes consecutive participant turns through one room-scoped model context" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)

    first = send_command(room, participant, "turn-one", "My name is River.")
    assert :ok = CallEngine.send_text(first)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}

    assert_receive {:test_model_inference_request, first_request,
                    [
                      %Message{role: :system, content: "Answer as a compact test assistant."},
                      %Message{role: :user, content: "My name is River."}
                    ]}

    send(first_request, {:test_model_inference_reply, {:ok, "Nice to meet you, River."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 3, text: "Nice to meet you, River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 4}}

    second = send_command(room, participant, "turn-two", "What is my name?")
    assert :ok = CallEngine.send_text(second)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 5}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 6}}

    assert_receive {:test_model_inference_request, second_request,
                    [
                      %Message{role: :system, content: "Answer as a compact test assistant."},
                      %Message{role: :user, content: "My name is River."},
                      %Message{role: :assistant, content: "Nice to meet you, River."},
                      %Message{role: :user, content: "What is my name?"}
                    ]}

    send(second_request, {:test_model_inference_reply, {:ok, "Your name is River."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 7, text: "Your name is River."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 8}}
  end

  test "reports a generation failure without ending the room or its model capability" do
    room_id = unique_id("room")
    {room, participant} = start_attached_room(room_id)
    failed = send_command(room, participant, "turn-failed", "Please fail once.")

    assert :ok = CallEngine.send_text(failed)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 1}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 2}}
    assert_receive {:test_model_inference_request, request, _messages}
    send(request, {:test_model_inference_reply, {:error, :upstream_unavailable}})

    assert_receive {:vxpipe_event,
                    %AgentTurnFailed{
                      sequence: 3,
                      correlation_id: "turn-failed",
                      reason: :provider_unavailable,
                      retryable: true
                    }}

    recovered = send_command(room, participant, "turn-recovered", "Please continue.")
    assert :ok = CallEngine.send_text(recovered)
    assert_receive {:vxpipe_event, %ParticipantTurnStarted{sequence: 4}}
    assert_receive {:vxpipe_event, %ParticipantTurnCompleted{sequence: 5}}
    assert_receive {:test_model_inference_request, recovered_request, _messages}
    send(recovered_request, {:test_model_inference_reply, {:ok, "Continuing."}})

    assert_receive {:vxpipe_event, %TextOutput{sequence: 6, text: "Continuing."}}
    assert_receive {:vxpipe_event, %AgentTurnCompleted{sequence: 7}}
  end

  defp start_attached_room(room_id) do
    assert {:ok, create} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               agent: :model_inference,
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
               connection_id: "conn-model",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(attach)
    {room, participant}
  end

  defp send_command(room, participant, correlation_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-model",
               correlation_id: correlation_id,
               content: content,
               audio_response: false,
               deadline: future_deadline()
             )

    command
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
