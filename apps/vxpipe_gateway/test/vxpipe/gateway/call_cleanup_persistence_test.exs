defmodule Vxpipe.Gateway.CallCleanupPersistenceTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor, TestCleanupCompletionRepository}

  setup do
    {:ok, command} =
      CreateRoom.new(
        tenant_id: "cleanup-storage",
        actor_id: "test",
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
        _ -> :ok
      end
    end)

    %{binding: binding, completion: completion_options(self())}
  end

  test "completion outlives its requester and remains responsive during persistence", c do
    parent = self()

    requester =
      start_supervised!(
        {Task,
         fn ->
           {:ok, tracker} =
             CallCleanupSupervisor.start_new(c.binding, nil, completion: c.completion)

           send(parent, {:tracker_started, tracker})
           receive do: (:finish -> :ok)
         end}
      )

    assert_receive {:tracker_started, tracker}
    requester_monitor = Process.monitor(requester)
    tracker_monitor = Process.monitor(tracker)
    send(requester, :finish)
    assert_receive {:DOWN, ^requester_monitor, :process, ^requester, :normal}
    stop_room(c.binding)

    assert_receive {:complete_cleanup, worker, binding, completed_at}, 1_000
    assert binding == c.binding
    assert %{status: :complete, completed_at: ^completed_at} = CallCleanup.snapshot(tracker)
    assert {:ok, ^tracker} = CallCleanupSupervisor.lookup(binding)
    send(worker, :complete)
    assert_receive {:DOWN, ^tracker_monitor, :process, ^tracker, :normal}, 1_000
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
  end

  test "retry retains the first timestamp after a failed result and a commit with lost result",
       c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, nil, completion: c.completion)
    monitor = Process.monitor(tracker)
    stop_room(c.binding)
    assert_receive {:complete_cleanup, first, binding, completed_at}, 1_000
    first_monitor = Process.monitor(first)
    send(first, :unavailable)
    assert_receive {:DOWN, ^first_monitor, :process, ^first, :normal}

    assert_receive {:complete_cleanup, second, ^binding, ^completed_at}, 1_000
    second_monitor = Process.monitor(second)
    send(second, :commit_then_die)
    assert_receive {:cleanup_committed, ^binding, ^completed_at}
    assert_receive {:DOWN, ^second_monitor, :process, ^second, :killed}
    assert_receive {:complete_cleanup, third, ^binding, ^completed_at}, 1_000
    assert %{completed_at: ^completed_at} = CallCleanup.snapshot(tracker)
    send(third, :complete)
    assert_receive {:DOWN, ^monitor, :process, ^tracker, :normal}, 1_000
  end

  test "a completion result cannot retire the tracker while its worker remains active", c do
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, nil, completion: c.completion)
    monitor = Process.monitor(tracker)
    stop_room(c.binding)
    assert_receive {:complete_cleanup, worker, _binding, _completed_at}, 1_000

    # Fault injection at our task protocol boundary: deliver success while the
    # repository still holds the actual worker. Retirement must also require DOWN.
    worker_ref = :sys.get_state(tracker).completion_task.ref
    send(tracker, {worker_ref, :ok})

    assert %{status: :complete} = CallCleanup.snapshot(tracker)
    refute_receive {:DOWN, ^monitor, :process, ^tracker, _}
    send(worker, :complete)
    assert_receive {:DOWN, ^monitor, :process, ^tracker, :normal}, 1_000
  end

  test "a blocked attempt times out before retry and its deadline survives tracker death", c do
    options = Keyword.put(c.completion, :timeout_ms, 500)
    {:ok, tracker} = CallCleanupSupervisor.start_new(c.binding, nil, completion: options)
    stop_room(c.binding)
    assert_receive {:complete_cleanup, first, binding, completed_at}, 1_000
    first_monitor = Process.monitor(first)
    assert_receive {:DOWN, ^first_monitor, :process, ^first, :killed}, 2_000
    assert_receive {:complete_cleanup, second, ^binding, ^completed_at}, 1_000
    second_monitor = Process.monitor(second)
    tracker_monitor = Process.monitor(tracker)
    Process.exit(tracker, :kill)
    assert_receive {:DOWN, ^tracker_monitor, :process, ^tracker, :killed}
    assert_receive {:DOWN, ^second_monitor, :process, ^second, :killed}, 2_000
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
  end

  test "seeded semantic obligations block storage until root DOWN and original-owner ack", c do
    root = start_supervised!({Task, fn -> receive do: (:finish -> :ok) end})

    {:ok, tracker} =
      CallCleanupSupervisor.start_new(c.binding, {:incoming_leg, root}, completion: c.completion)

    monitor = Process.monitor(tracker)
    {:ok, _} = CallCleanup.observe(tracker)
    stop_room(c.binding)
    assert_receive {:call_cleanup_changed, ^tracker, %{status: :pending}}, 1_000
    refute_receive {:complete_cleanup, _, _, _}
    :ok = CallCleanup.acknowledge(tracker, root, :complete)
    assert %{status: :pending} = CallCleanup.snapshot(tracker)
    send(root, :finish)
    assert_receive {:complete_cleanup, worker, _, _}, 1_000
    send(worker, :complete)
    assert_receive {:DOWN, ^monitor, :process, ^tracker, :normal}, 1_000
  end

  test "invalid completion settings cannot silently disable persistence", c do
    for options <- [[timeout_ms: 0], [retry_ms: -1], [calls_options: :invalid]] do
      assert {:error, :invalid_completion_options} =
               CallCleanupSupervisor.start_new(c.binding, nil, completion: options)
    end

    assert {:error, :not_found} = CallCleanupSupervisor.lookup(c.binding)
  end

  defp completion_options(observer) do
    [
      calls_options: [
        call_repository: {TestCleanupCompletionRepository, observer},
        publication_enabled: false
      ],
      timeout_ms: 5_000,
      retry_ms: 1
    ]
  end

  defp stop_room(binding),
    do:
      assert(
        :ok == CallEngine.end_call(binding.tenant_key, binding.room_id, binding.incarnation_id)
      )
end
