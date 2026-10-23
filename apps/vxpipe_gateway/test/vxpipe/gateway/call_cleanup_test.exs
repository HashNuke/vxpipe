defmodule Vxpipe.Gateway.CallCleanupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}

  setup do
    {:ok, command} =
      CreateRoom.new(
        tenant_id: "cleanup-tenant",
        actor_id: "cleanup-test",
        deadline: DateTime.add(DateTime.utc_now(), 60, :second)
      )

    {:ok, room} = CallEngine.create_room(command)

    binding = %{
      tenant_key: command.tenant_id,
      call_id: "call-#{room.room_id}",
      room_id: room.room_id,
      incarnation_id: room.incarnation_id
    }

    on_exit(fn ->
      CallEngine.end_call(binding.tenant_key, binding.room_id, binding.incarnation_id)

      case CallCleanupSupervisor.lookup(binding) do
        {:ok, tracker} -> DynamicSupervisor.terminate_child(CallCleanupSupervisor, tracker)
        {:error, :not_found} -> :ok
      end
    end)

    %{binding: binding}
  end

  test "completion requires sealed registration, engine cleanup, semantic ack and resource-tree DOWN",
       c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    assert {:ok, %{status: :open}} = CallCleanup.observe(tracker)
    worker = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    assert :ok = CallCleanup.register(tracker, :session, worker)
    assert :ok = CallCleanup.register(tracker, :session, worker)
    assert :ok = CallCleanup.seal(tracker)
    assert {:error, :sealed} = CallCleanup.register(tracker, :session, self())
    stop_room(c.binding)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{engine_outcome: :complete, status: :pending}},
                   1_000

    assert :ok = CallCleanup.acknowledge(tracker, worker, :complete)
    assert %{status: :pending} = CallCleanup.snapshot(tracker)
    send(worker, :finish)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{status: :complete, completed_at: completed}},
                   1_000

    assert %DateTime{} = completed
    assert %{status: :complete, completed_at: ^completed} = CallCleanup.snapshot(tracker)
    assert {:error, :completed} = CallCleanup.acknowledge(tracker, worker, :unknown)
    assert {:ok, ^tracker} = CallCleanupSupervisor.lookup(c.binding)
  end

  test "a live original owner may resolve unknown after an orderly resource exit", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    {:ok, _} = CallCleanup.observe(tracker)
    worker = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    :ok = CallCleanup.register(tracker, :incoming_leg, worker)
    :ok = CallCleanup.acknowledge(tracker, worker, :unknown)
    assert %{status: :open, uncertain?: true} = CallCleanup.snapshot(tracker)
    send(worker, :finish)
    stop_room(c.binding)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{engine_outcome: :complete, status: :unknown}},
                   1_000

    assert :ok = CallCleanup.acknowledge(tracker, worker, :complete)

    assert_receive {:call_cleanup_changed, ^tracker, %{status: :complete, uncertain?: false}},
                   1_000
  end

  test "abnormal resource termination cannot become complete through a later ack", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    {:ok, _} = CallCleanup.observe(tracker)
    worker = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    :ok = CallCleanup.register(tracker, :web_rtc, worker)
    :ok = CallCleanup.acknowledge(tracker, worker, :complete)
    Process.exit(worker, :kill)
    stop_room(c.binding)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{engine_outcome: :complete, status: :unknown}},
                   1_000

    assert :ok = CallCleanup.acknowledge(tracker, worker, :complete)
    assert %{status: :unknown, completed_at: nil} = CallCleanup.snapshot(tracker)
  end

  test "only the original registering caller can acknowledge a resource", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    resource = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    :ok = CallCleanup.register(tracker, :session, resource)
    parent = self()

    start_supervised!(
      {Task,
       fn ->
         send(parent, {:foreign_ack, CallCleanup.acknowledge(tracker, resource, :complete)})
         send(parent, {:foreign_registration, CallCleanup.register(tracker, :session, resource)})
       end},
      id: :foreign
    )

    assert_receive {:foreign_ack, {:error, :invalid_owner}}
    assert_receive {:foreign_registration, {:error, :invalid_owner}}
    assert :ok = CallCleanup.acknowledge(tracker, resource, :complete)
  end

  test "tracker loss is not silently reconstructed by recovery lookup", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    assert {:error, {:already_started, ^tracker}} = CallCleanupSupervisor.start_new(c.binding)
    monitor = Process.monitor(tracker)
    Process.exit(tracker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^tracker, :killed}
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
  end

  test "binding identity ignores ancillary admission fields", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    extended = Map.put(c.binding, :admission_metadata, :extra)

    assert {:ok, ^tracker} = CallCleanupSupervisor.lookup(extended)
    assert {:error, {:already_started, ^tracker}} = CallCleanupSupervisor.start_new(extended)
    assert %{binding: binding} = CallCleanup.snapshot(tracker)
    assert binding == c.binding
  end

  test "a missing or replacement engine incarnation cannot seed a tracker", c do
    stale = %{c.binding | incarnation_id: "replacement"}
    assert {:error, :room_unavailable} = CallCleanupSupervisor.start_new(stale)
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(stale)
  end

  test "an existing carrier root is tracked from startup before immediate engine completion", c do
    root = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    owner = self()

    assert {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, {:incoming_leg, root})

    assert {:ok, %{resources: %{^root => %{kind: :incoming_leg, owner: ^owner}}}} =
             CallCleanup.observe(tracker)

    stop_room(c.binding)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{engine_outcome: :complete, status: :pending}},
                   1_000

    assert :ok = CallCleanup.acknowledge(tracker, root, :complete)
    send(root, :finish)
    assert_receive {:call_cleanup_changed, ^tracker, %{status: :complete}}, 1_000
  end

  test "seed ownership belongs to the admission caller and survives as unknown when it dies", c do
    root = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
    parent = self()

    owner =
      start_supervised!(
        {Task,
         fn ->
           {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, {:incoming_leg, root})
           send(parent, {:tracker_started, tracker})
           receive do: (:finish -> :ok)
         end},
        id: :admission_owner
      )

    assert_receive {:tracker_started, tracker}
    assert {:ok, %{resources: %{^root => %{owner: ^owner}}}} = CallCleanup.observe(tracker)
    assert {:error, :invalid_owner} = CallCleanup.acknowledge(tracker, root, :complete)
    send(owner, :finish)
    stop_room(c.binding)
    send(root, :finish)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{
                      engine_outcome: :complete,
                      status: :unknown,
                      resources: %{^root => %{owner_alive?: false, root_outcome: :complete}}
                    }},
                   1_000
  end

  test "seeded startup cannot turn a missing exact engine into completion evidence", c do
    stale = %{c.binding | incarnation_id: "replacement"}

    assert {:error, :room_unavailable} =
             CallCleanupSupervisor.start_new(stale, {:incoming_leg, self()})

    assert {:error, :not_found} = CallCleanupSupervisor.lookup(stale)
  end

  for {acknowledgement, expected} <- [pending: :unknown, complete: :complete] do
    test "owner death with #{acknowledgement} acknowledgement retains #{expected} evidence", c do
      {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
      {:ok, _} = CallCleanup.observe(tracker)
      root = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})
      parent = self()

      owner =
        start_supervised!(
          {Task,
           fn ->
             :ok = CallCleanup.register(tracker, :outgoing_leg, root)

             if unquote(acknowledgement) == :complete do
               :ok = CallCleanup.acknowledge(tracker, root, :complete)
             end

             send(parent, {:registered, self()})
             receive do: (:finish -> :ok)
           end},
          id: :acknowledgement_owner
        )

      assert_receive {:registered, ^owner}
      send(owner, :finish)

      assert_receive {:call_cleanup_changed, ^tracker,
                      %{resources: %{^root => %{owner_alive?: false}}}},
                     1_000

      stop_room(c.binding)
      send(root, :finish)

      assert_receive {:call_cleanup_changed, ^tracker,
                      %{
                        engine_outcome: :complete,
                        status: unquote(expected),
                        resources: %{^root => %{root_outcome: :complete}}
                      }},
                     1_000
    end
  end

  test "abnormal engine termination remains unknown even with no registered resources", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding)
    {:ok, _} = CallCleanup.observe(tracker)

    # Fault injection at the engine boundary: kill the exact supervision root,
    # not just the room authority whose normal exit initiates orderly cleanup.
    engine =
      GenServer.whereis(
        {:via, Registry,
         {CallEngine.RoomRegistry,
          {:room_incarnation, c.binding.tenant_key, c.binding.room_id, c.binding.incarnation_id}}}
      )

    Process.exit(engine, :kill)

    assert_receive {:call_cleanup_changed, ^tracker,
                    %{sealed?: true, engine_outcome: :unknown, status: :unknown}},
                   1_000

    assert :ok = CallCleanup.seal(tracker)
    assert %{status: :unknown, completed_at: nil} = CallCleanup.snapshot(tracker)
  end

  defp stop_room(binding) do
    assert :ok = CallEngine.end_call(binding.tenant_key, binding.room_id, binding.incarnation_id)
  end
end
