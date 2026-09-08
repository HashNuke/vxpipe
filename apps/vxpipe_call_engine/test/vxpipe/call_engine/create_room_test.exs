defmodule Vxpipe.CallEngine.CreateRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.Error
  alias Vxpipe.CallEngine.Room.Snapshot

  test "creates one supervised room incarnation and returns its public snapshot" do
    room_id = unique_room_id()

    assert {:ok, command} =
             CreateRoom.new(
               id: "cmd-create-room",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, snapshot} = CallEngine.create_room(command)

    assert Snapshot.to_public(snapshot) == %{
             "created_by_actor_id" => "actor-demo",
             "created_by_command_id" => "cmd-create-room",
             "incarnation_id" => snapshot.incarnation_id,
             "lifecycle" => "open",
             "room_id" => room_id,
             "tenant_id" => "tenant-demo"
           }

    assert String.starts_with?(snapshot.incarnation_id, "rinc_")

    assert {:error, %Error{code: :room_already_exists, retryable: false}} =
             CallEngine.create_room(command)
  end

  test "rejects a command whose deadline has elapsed" do
    assert {:ok, command} =
             CreateRoom.new(
               id: "cmd-expired",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: unique_room_id(),
               deadline: DateTime.add(DateTime.utc_now(), -1, :second)
             )

    assert {:error, %Error{code: :deadline_exceeded, retryable: false}} =
             CallEngine.create_room(command)
  end

  test "ends the room incarnation when its authority terminates" do
    existing_incarnations = incarnation_pids()
    room_id = unique_room_id()

    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: room_id,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, _snapshot} = CallEngine.create_room(command)

    assert [incarnation] = incarnation_pids() -- existing_incarnations

    assert [{authority, _value}] =
             Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {"tenant-demo", room_id})

    authority_monitor = Process.monitor(authority)
    incarnation_monitor = Process.monitor(incarnation)
    Process.exit(authority, :kill)

    assert_receive {:DOWN, ^authority_monitor, :process, ^authority, :killed}
    assert_receive {:DOWN, ^incarnation_monitor, :process, ^incarnation, :shutdown}
  end

  defp unique_room_id do
    "room-test-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp incarnation_pids do
    for {_id, pid, :supervisor, _modules} <-
          DynamicSupervisor.which_children(Vxpipe.CallEngine.RoomSupervisor),
        do: pid
  end
end
