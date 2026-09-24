defmodule Vxpipe.CallEngine.TextTurnTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.Command.{
    AttachConnection,
    ContinueAgent,
    CreateRoom,
    JoinParticipant,
    SendText
  }

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Error

  alias Vxpipe.CallEngine.Event.{
    AgentTurnCompleted,
    ParticipantTurnCompleted,
    ParticipantTurnStarted,
    TextOutput,
    ToolCallCancelled,
    ToolCallCompleted,
    ToolCallStarted
  }

  alias Vxpipe.CallEngine.Tool.Call

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

    assert {:ok,
            %ConnectionAttachment{room_monitor: room_monitor, media_ingress: nil} = attachment} =
             CallEngine.attach_connection(attach_command)

    assert is_reference(room_monitor)
    assert is_pid(attachment.room_authority)
    assert :disabled = CallEngine.room_audio_configuration(attachment)

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

  test "projects an accepted background result through an agent-only continuation turn" do
    room_id = unique_id("room-background")
    {room, participant, authority, capability} = start_attached_deterministic_room(room_id)

    continuation = %ContinueAgent{
      id: "cmd-background-continuation",
      tenant_id: "tenant-demo",
      room_id: room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: "conn-background",
      correlation_id: "continuation-background",
      content: "private engine observation",
      audio_response: false,
      source_command_id: "cmd-background-source",
      tool_call_id: "tool-background",
      tool_name: "wait_for_test"
    }

    call = %Call{id: "tool-background", name: "wait_for_test", arguments: %{}}

    send(authority, {:vxpipe_capability_continuation_started, capability, continuation})
    send(authority, {:vxpipe_capability_tool_started, capability, continuation, call})

    assert_receive {:vxpipe_event,
                    %ToolCallStarted{
                      sequence: 1,
                      command_id: "cmd-background-continuation",
                      tool_call_id: "tool-background"
                    }}

    send(
      authority,
      {:vxpipe_capability_tool_accepted, capability, continuation, call,
       %{"invocation_id" => "tool-background", "status" => "running"}}
    )

    send(authority, {:vxpipe_capability_text, capability, continuation, "Still working."})
    send(authority, {:vxpipe_capability_text_complete, capability, continuation})

    assert_receive {:vxpipe_event,
                    %TextOutput{
                      sequence: 2,
                      command_id: "cmd-background-continuation",
                      text: "Still working."
                    }}

    assert_receive {:vxpipe_event,
                    %AgentTurnCompleted{
                      sequence: 3,
                      command_id: "cmd-background-continuation"
                    }}

    send(
      authority,
      {:vxpipe_capability_tool_completed, capability, continuation, call, %{"released" => true}}
    )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      sequence: 4,
                      command_id: "cmd-background-continuation",
                      tool_call_id: "tool-background",
                      result: %{"released" => true}
                    }}

    refute_receive {:vxpipe_event, %ParticipantTurnStarted{}}
    refute_receive {:vxpipe_event, %ParticipantTurnCompleted{}}
  end

  test "an accepted background call survives interruption of its originating turn" do
    room_id = unique_id("room-background-interruption")
    {room, participant, authority, capability} = start_attached_deterministic_room(room_id)

    originating = %ContinueAgent{
      id: "cmd-background-originating",
      tenant_id: "tenant-demo",
      room_id: room_id,
      incarnation_id: room.incarnation_id,
      participant_id: participant.participant_id,
      connection_id: "conn-background",
      correlation_id: "continuation-originating",
      content: "private engine observation",
      audio_response: false,
      source_command_id: "cmd-background-source",
      tool_call_id: "tool-survives",
      tool_name: "wait_for_test"
    }

    call = %Call{id: "tool-survives", name: "wait_for_test", arguments: %{}}

    send(authority, {:vxpipe_capability_continuation_started, capability, originating})
    send(authority, {:vxpipe_capability_tool_started, capability, originating, call})

    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "tool-survives"}}

    send(
      authority,
      {:vxpipe_capability_tool_accepted, capability, originating, call,
       %{"invocation_id" => "tool-survives", "status" => "running"}}
    )

    assert {:ok, replacement} =
             SendText.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               incarnation_id: room.incarnation_id,
               participant_id: participant.participant_id,
               connection_id: "conn-background",
               correlation_id: "caller-replacement",
               content: "keep talking",
               run_immediately: true,
               audio_response: false,
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(replacement)
    refute_receive {:vxpipe_event, %ToolCallCancelled{tool_call_id: "tool-survives"}}

    send(
      authority,
      {:vxpipe_capability_tool_completed, capability, originating, call, %{"released" => true}}
    )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      command_id: "cmd-background-originating",
                      tool_call_id: "tool-survives",
                      result: %{"released" => true}
                    }}
  end

  defp start_attached_deterministic_room(room_id) do
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
               connection_id: "conn-background",
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(attach)

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-demo", room_id})

    %{text_capability: %{pid: capability}} = :sys.get_state(authority)
    {room, participant, authority, capability}
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
