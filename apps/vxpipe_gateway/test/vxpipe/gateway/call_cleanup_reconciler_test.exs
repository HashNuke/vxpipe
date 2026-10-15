defmodule Vxpipe.Gateway.CallCleanupReconcilerTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.Gateway.{CallCleanupReconciler, CallCleanupSupervisor}
  alias Vxpipe.Gateway.TestCleanupReconciliationRepository

  @completed ~U[2026-10-15 12:00:00.000000Z]
  @intent ~U[2026-10-15 12:01:00.000000Z]

  test "startup discovers durable intent and stops only the exact verified incarnation" do
    binding = room()
    {:ok, tracker} = CallCleanupSupervisor.start_new(binding)
    {:ok, _} = Vxpipe.Gateway.CallCleanup.observe(tracker)
    reconciler()
    assert_receive {:cleanup_scan, scan, nil, 2}
    send(scan, {:scan_result, {:ok, %{items: [row(binding)], next_cursor: nil}}})

    assert_receive {:call_cleanup_changed, ^tracker, %{engine_outcome: :complete}}, 1_000

    assert {:error, :room_unavailable} =
             CallEngine.monitor_room_completion(
               binding.tenant_key,
               binding.room_id,
               binding.incarnation_id
             )
  end

  test "unverified or absent intent cannot stop an active room or fabricate membership" do
    binding = room()
    service = reconciler()
    assert_receive {:cleanup_scan, scan, nil, 2}

    rows = [
      %{row(binding) | incarnation_binding_verified: false},
      %{row(binding) | hangup_requested_at: nil}
    ]

    cursor = %{after_id: 2, through_id: 3}
    send(scan, {:scan_result, {:ok, %{items: rows, next_cursor: cursor}}})
    assert_receive {:cleanup_scan, next, ^cursor, 2}, 1_000

    assert {:ok, monitor} =
             CallEngine.monitor_room_completion(
               binding.tenant_key,
               binding.room_id,
               binding.incarnation_id
             )

    Process.demonitor(monitor, [:flush])
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    send(next, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
    assert :ok = CallCleanupReconciler.wake(service)
  end

  test "stale intent cannot terminate a replacement incarnation" do
    binding = room()
    reconciler()
    assert_receive {:cleanup_scan, scan, nil, 2}
    stale = %{row(binding) | incarnation_id: "retired-incarnation"}
    cursor = %{after_id: 1, through_id: 2}
    send(scan, {:scan_result, {:ok, %{items: [stale], next_cursor: cursor}}})
    assert_receive {:cleanup_scan, next, ^cursor, 2}, 1_000

    assert {:ok, monitor} =
             CallEngine.monitor_room_completion(
               binding.tenant_key,
               binding.room_id,
               binding.incarnation_id
             )

    Process.demonitor(monitor, [:flush])
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    send(next, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
  end

  test "completed cleanup replays later intent without recreating a tracker" do
    binding = %{
      tenant_key: "cleanup-replay",
      call_id: "call",
      room_id: "room",
      incarnation_id: "owner"
    }

    service = reconciler()
    assert_receive {:cleanup_scan, scan, nil, 2}
    cursor = %{after_id: 1, through_id: 2}
    send(scan, {:scan_result, {:ok, %{items: [row(binding, @completed)], next_cursor: cursor}}})
    assert_receive {:cleanup_replay, worker, ^binding, @completed}, 1_000
    assert {:error, :not_found} = CallCleanupSupervisor.lookup(binding)
    assert :ok = CallCleanupReconciler.wake(service)
    send(worker, :complete)
    assert_receive {:cleanup_scan, next, ^cursor, 2}, 1_000
    send(next, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
    assert_receive {:cleanup_scan, restarted, nil, 2}, 1_000
    send(restarted, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
  end

  test "bounded workers advance past timeout and retry unresolved rows in the next cycle" do
    service = reconciler(concurrency: 1, timeout_ms: 500)
    assert_receive {:cleanup_scan, scan, nil, 2}

    first =
      row(
        %{tenant_key: "cleanup-fair", call_id: "first", room_id: "room-1", incarnation_id: "one"},
        @completed
      )

    second =
      row(
        %{
          tenant_key: "cleanup-fair",
          call_id: "second",
          room_id: "room-2",
          incarnation_id: "two"
        },
        @completed
      )

    cursor = %{after_id: 2, through_id: 3}
    send(scan, {:scan_result, {:ok, %{items: [first, second], next_cursor: cursor}}})
    assert_receive {:cleanup_replay, blocked, %{call_id: "first"}, @completed}, 1_000
    monitor = Process.monitor(blocked)
    refute_receive {:cleanup_replay, _, %{call_id: "second"}, _}, 20
    assert_receive {:DOWN, ^monitor, :process, ^blocked, :killed}, 1_000
    assert_receive {:cleanup_replay, later, %{call_id: "second"}, @completed}, 1_000
    send(later, :complete)
    assert_receive {:cleanup_scan, next, ^cursor, 2}, 1_000
    assert :ok = CallCleanupReconciler.wake(service)
    send(next, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
    assert_receive {:cleanup_scan, repeated, nil, 2}, 1_000
    send(repeated, {:scan_result, {:ok, %{items: [first], next_cursor: nil}}})
    assert_receive {:cleanup_replay, retried, %{call_id: "first"}, @completed}, 1_000
    send(retried, :complete)
  end

  test "scan failure retries its cursor and worker deadlines survive reconciler death" do
    service = reconciler(timeout_ms: 500, retry_ms: 1)
    assert_receive {:cleanup_scan, first, nil, 2}
    cursor = %{after_id: 1, through_id: 2}
    send(first, {:scan_result, {:ok, %{items: [], next_cursor: cursor}}})
    assert_receive {:cleanup_scan, failed, ^cursor, 2}, 1_000
    send(failed, {:scan_result, {:error, :unavailable}})
    assert_receive {:cleanup_scan, blocked, ^cursor, 2}, 1_000
    worker_monitor = Process.monitor(blocked)
    service_monitor = Process.monitor(service)
    :ok = stop_supervised(CallCleanupReconciler)
    assert_receive {:DOWN, ^service_monitor, :process, ^service, :shutdown}
    assert_receive {:DOWN, ^worker_monitor, :process, ^blocked, :killed}, 1_000
    reconciler()
    assert_receive {:cleanup_scan, restarted, nil, 2}, 1_000
    send(restarted, {:scan_result, {:ok, %{items: [], next_cursor: nil}}})
  end

  defp reconciler(extra \\ []) do
    options = [
      name: nil,
      calls_options: [
        call_repository: {TestCleanupReconciliationRepository, self()},
        publication_enabled: false
      ],
      page_size: 2,
      concurrency: 2,
      timeout_ms: 5_000,
      interval_ms: 60_000,
      retry_ms: 10
    ]

    start_supervised!({CallCleanupReconciler, Keyword.merge(options, extra)})
  end

  defp row(binding, completed \\ nil) do
    Map.merge(binding, %{
      id: 1,
      incarnation_binding_verified: true,
      hangup_requested_at: @intent,
      gateway_cleanup_required: true,
      gateway_cleanup_completed_at: completed
    })
  end

  defp room do
    {:ok, command} =
      CreateRoom.new(
        tenant_id: "cleanup-reconcile",
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

    binding
  end
end
