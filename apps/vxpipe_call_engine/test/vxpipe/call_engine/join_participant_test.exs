defmodule Vxpipe.CallEngine.JoinParticipantTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.{CreateRoom, JoinParticipant}
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Participant.Snapshot

  test "admits one participant beneath an existing room incarnation" do
    room_id = unique_id("room")
    participant_id = unique_id("participant")
    room = create_room(room_id)

    assert {:ok, command} =
             JoinParticipant.new(
               id: "cmd-join-participant",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               participant_id: participant_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, participant} = CallEngine.join_participant(command)

    assert Snapshot.to_public(participant) == %{
             "created_by_actor_id" => "actor-demo",
             "created_by_command_id" => "cmd-join-participant",
             "incarnation_id" => room.incarnation_id,
             "participant_id" => participant_id,
             "role" => "human",
             "room_id" => room_id,
             "state" => "joined",
             "tenant_id" => "tenant-demo"
           }

    assert {:error, %Error{code: :participant_already_exists}} =
             CallEngine.join_participant(command)
  end

  test "rejects admission to a room that does not exist" do
    assert {:ok, command} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: unique_id("missing-room"),
               role: :human,
               deadline: future_deadline()
             )

    assert {:error, %Error{code: :room_not_found}} = CallEngine.join_participant(command)
  end

  test "terminates admitted participants with their room incarnation" do
    room_id = unique_id("room")
    participant_id = unique_id("participant")
    _room = create_room(room_id)

    assert {:ok, command} =
             JoinParticipant.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               participant_id: participant_id,
               role: :human,
               deadline: future_deadline()
             )

    assert {:ok, _participant} = CallEngine.join_participant(command)

    assert [{participant_authority, _value}] =
             Registry.lookup(
               Vxpipe.CallEngine.RoomRegistry,
               {:participant, "tenant-demo", room_id, participant_id}
             )

    assert [{room_authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-demo", room_id})

    participant_monitor = Process.monitor(participant_authority)
    Process.exit(room_authority, :kill)

    assert_receive {:DOWN, ^participant_monitor, :process, ^participant_authority, :shutdown}
  end

  defp create_room(room_id) do
    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(command)
    room
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
