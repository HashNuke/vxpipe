defmodule Vxpipe.CallEngine.TextTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{AttachConnection, CreateRoom, JoinParticipant, SendText}
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Error

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput
  }

  test "routes attached participant text through the room's deterministic agent" do
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
               connection_id: "conn-test",
               deadline: future_deadline()
             )

    assert {:ok, %ConnectionAttachment{room_monitor: room_monitor, media_ingress: nil}} =
             CallEngine.attach_connection(attach_command)

    assert is_reference(room_monitor)

    assert {:ok, send_command} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-test",
               correlation_id: "client-message-1",
               content: "hello",
               run_immediately: true,
               audio_response: true,
               deadline: future_deadline()
             )

    unauthorized = Task.async(fn -> CallEngine.send_text(send_command) end)

    assert {:error, %Error{code: :connection_not_attached}} = Task.await(unauthorized)
    assert :ok = CallEngine.send_text(send_command)

    assert_receive {:vxpipe_event,
                    %ParticipantTurnStarted{
                      id: "evt_" <> _,
                      sequence: 1,
                      tenant_id: "tenant-demo",
                      room_id: ^room_id,
                      incarnation_id: incarnation_id,
                      participant_id: source_participant_id,
                      connection_id: "conn-test",
                      command_id: command_id,
                      correlation_id: "client-message-1",
                      modality: :text
                    }}

    assert_receive {:vxpipe_event,
                    %ParticipantTurnCompleted{
                      id: "evt_" <> _,
                      sequence: 2,
                      tenant_id: "tenant-demo",
                      room_id: ^room_id,
                      incarnation_id: ^incarnation_id,
                      participant_id: ^source_participant_id,
                      connection_id: "conn-test",
                      command_id: ^command_id,
                      correlation_id: "client-message-1",
                      modality: :text
                    }}

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      id: "evt_" <> _,
                      sequence: 3,
                      tenant_id: "tenant-demo",
                      room_id: ^room_id,
                      incarnation_id: ^incarnation_id,
                      participant_id: agent_participant_id,
                      source_participant_id: ^source_participant_id,
                      connection_id: "conn-test",
                      command_id: ^command_id,
                      correlation_id: "client-message-1",
                      text: "Echo: hello",
                      aggregated_by: :sentence,
                      will_be_spoken: false
                    }}

    assert incarnation_id == room.incarnation_id
    assert agent_participant_id == create_command.agent_participant_id
    assert source_participant_id == participant.participant_id
    assert command_id == send_command.id

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{
                      id: "evt_" <> _,
                      sequence: 4,
                      tenant_id: "tenant-demo",
                      room_id: ^room_id,
                      incarnation_id: ^incarnation_id,
                      participant_id: ^agent_participant_id,
                      source_participant_id: ^source_participant_id,
                      connection_id: "conn-test",
                      command_id: ^command_id,
                      correlation_id: "client-message-1"
                    }}

    assert [{participant_authority, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant, "tenant-demo", room_id, participant.participant_id}
             )

    Process.exit(participant_authority, :kill)

    assert_receive {:vxpipe_connection_unavailable, :participant_unavailable}
    Process.demonitor(room_monitor, [:flush])
  end

  test "does not attach a participant before the room has an agent path" do
    room_id = unique_id("room")

    assert {:ok, create_command} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
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
               connection_id: "conn-no-agent",
               deadline: future_deadline()
             )

    assert {:error, %Error{code: :agent_not_ready, retryable: true}} =
             CallEngine.attach_connection(attach_command)
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
