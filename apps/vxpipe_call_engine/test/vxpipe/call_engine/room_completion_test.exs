defmodule Vxpipe.CallEngine.RoomCompletionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom

  test "completion observes owned worker shutdown after the room authority exits" do
    {command, room} = create_room()
    assert {:ok, completion} = monitor_completion(command, room)

    assert {:ok, authority} =
             CallEngine.monitor_room(command.tenant_id, command.room_id, room.incarnation_id)

    owner = self()

    capability_supervisor =
      {:via, Registry, {CallEngine.RoomRegistry, {:capability_supervisor, room.incarnation_id}}}

    assert {:ok, worker} =
             DynamicSupervisor.start_child(
               capability_supervisor,
               {Task,
                fn ->
                  Process.flag(:trap_exit, true)
                  send(owner, {:cleanup_worker_ready, self()})

                  receive do
                    {:EXIT, _supervisor, :shutdown} ->
                      send(owner, {:cleanup_worker_stopping, self()})

                      receive do
                        :finish_cleanup -> :ok
                      end
                  end
                end}
             )

    on_exit(fn -> send(worker, :finish_cleanup) end)
    assert_receive {:cleanup_worker_ready, ^worker}
    assert :ok = CallEngine.end_call(command.tenant_id, command.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^authority, :process, _, _}, 1_000
    assert_receive {:cleanup_worker_stopping, ^worker}, 1_000
    refute_received {:DOWN, ^completion, :process, _, _}

    # The exact supervisor remains discoverable during cleanup even though its
    # authority has already left the registry.
    assert {:ok, late_completion} = monitor_completion(command, room)
    send(worker, :finish_cleanup)
    assert_receive {:DOWN, ^completion, :process, supervisor, _}, 1_000
    assert_receive {:DOWN, ^late_completion, :process, ^supervisor, _}, 1_000
    assert {:error, :room_unavailable} = monitor_completion(command, room)
  end

  test "completion lookup cannot adopt a foreign or replacement incarnation" do
    {command, room} = create_room()

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room_completion("foreign", command.room_id, room.incarnation_id)

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room_completion(command.tenant_id, "foreign", room.incarnation_id)

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room_completion(command.tenant_id, command.room_id, "stale")

    assert {:ok, completion} = monitor_completion(command, room)
    assert :ok = CallEngine.end_call(command.tenant_id, command.room_id, room.incarnation_id)
    assert_receive {:DOWN, ^completion, :process, _, _}, 1_000

    assert {:ok, replacement} = CallEngine.create_room(command)
    assert replacement.incarnation_id != room.incarnation_id
    assert {:error, :room_unavailable} = monitor_completion(command, room)
    assert {:ok, replacement_completion} = monitor_completion(command, replacement)

    assert :ok =
             CallEngine.end_call(command.tenant_id, command.room_id, replacement.incarnation_id)

    assert_receive {:DOWN, ^replacement_completion, :process, _, _}, 1_000
  end

  defp monitor_completion(command, room),
    do:
      CallEngine.monitor_room_completion(command.tenant_id, command.room_id, room.incarnation_id)

  defp create_room do
    assert {:ok, command} =
             CreateRoom.new(
               tenant_id: "completion-tenant",
               actor_id: "test",
               deadline: DateTime.add(DateTime.utc_now(), 60, :second)
             )

    assert {:ok, room} = CallEngine.create_room(command)

    on_exit(fn ->
      CallEngine.end_call(command.tenant_id, command.room_id, room.incarnation_id)
    end)

    {command, room}
  end
end
