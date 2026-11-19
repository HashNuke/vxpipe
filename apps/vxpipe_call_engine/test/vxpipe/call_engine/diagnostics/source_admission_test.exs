defmodule Vxpipe.CallEngine.Diagnostics.SourceAdmissionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentLease, SourceAdmission}

  setup do
    gate = AttachmentLease.gate(1)
    pool = start_supervised!({SourceAdmission, name: via(), gate: gate})

    first =
      start_supervised!({DynamicSupervisor, name: via(), strategy: :one_for_one}, id: :first)

    second =
      start_supervised!({DynamicSupervisor, name: via(), strategy: :one_for_one}, id: :second)

    %{gate: gate, pool: pool, first: first, second: second}
  end

  test "two room worker supervisors share a slot until the admitted worker exits", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    {:ok, worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    assert :ok = SourceAdmission.adopt(c.pool, lease)
    assert %{active_sources: 1, occupied_slots: 1} = SourceAdmission.status(c.pool)
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    assert :ok = SourceAdmission.cancel(c.pool, lease)
    refute AttachmentLease.current?(lease)
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    stop_worker(c.first, worker)
    {:ok, next} = SourceAdmission.reserve(c.pool, self())

    assert {:ok, _replacement} =
             SourceAdmission.start_worker(c.pool, next, c.second, worker_spec())

    assert :ok = SourceAdmission.adopt(c.pool, next)
    assert AttachmentLease.pending(c.gate) == 1
  end

  test "one reservation cannot start a second worker", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    assert {:ok, worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    assert :ok = SourceAdmission.adopt(c.pool, lease)
    parent = self()

    spec =
      Supervisor.child_spec(
        {Agent,
         fn ->
           send(parent, :extra_started)
           :idle
         end},
        restart: :temporary
      )

    assert {:error, :unavailable} = SourceAdmission.start_worker(c.pool, lease, c.second, spec)
    refute_received :extra_started
    assert [{_, ^worker, _, _}] = DynamicSupervisor.which_children(c.first)
  end

  test "interrupted startup retains unknown-child debt", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())

    assert {:error, :unavailable} =
             SourceAdmission.start_worker(c.pool, lease, __MODULE__.Absent, worker_spec())

    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    assert AttachmentLease.pending(c.gate) == 1
  end

  test "started but unadopted suspended worker retains capacity after cancellation", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    {:ok, worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    :ok = :sys.suspend(worker)

    try do
      :ok = SourceAdmission.cancel(c.pool, lease)
      assert {:error, :unavailable} = SourceAdmission.adopt(c.pool, lease)
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    after
      :sys.resume(worker)
    end

    stop_worker(c.first, worker)
    assert {:ok, _next} = SourceAdmission.reserve(c.pool, self())
  end

  test "room-service death revokes but cannot release a still-running worker", c do
    {:ok, owner} = DynamicSupervisor.start_child(c.first, worker_spec())
    {:ok, lease} = SourceAdmission.reserve(c.pool, owner)
    {:ok, worker} = SourceAdmission.start_worker(c.pool, lease, c.second, worker_spec())
    :ok = SourceAdmission.adopt(c.pool, lease)
    stop_worker(c.first, owner)
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    refute AttachmentLease.current?(lease)
    stop_worker(c.second, worker)
    assert {:ok, _next} = SourceAdmission.reserve(c.pool, self())
  end

  test "cancelled unresolved startup keeps debt until its operation finishes", c do
    parent = self()
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())

    {:ok, helper} =
      DynamicSupervisor.start_child(
        c.first,
        {Task,
         fn ->
           AttachmentLease.operation(lease, fn ->
             send(parent, :entered)

             receive do
               :finish -> :ok
             end
           end)
         end}
      )

    assert_receive :entered
    :ok = SourceAdmission.cancel(c.pool, lease)
    assert {:error, :capacity_unavailable} = SourceAdmission.reserve(c.pool, self())
    assert {:error, :unavailable} = SourceAdmission.adopt(c.pool, lease)
    monitor = Process.monitor(helper)
    send(helper, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^helper, :normal}
    assert {:ok, _next} = SourceAdmission.reserve(c.pool, self())
  end

  test "failed child startup releases its reservation", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    bad = %{id: :bad, start: {Agent, :start_link, [fn -> exit(:fixture_failure) end]}}
    assert {:error, _} = SourceAdmission.start_worker(c.pool, lease, c.first, bad)
    assert {:ok, _next} = SourceAdmission.reserve(c.pool, self())
  end

  test "tracker replacement reuses gate debt instead of admitting over a surviving worker", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    {:ok, worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    :ok = SourceAdmission.adopt(c.pool, lease)
    :ok = :sys.suspend(worker)

    try do
      :ok = stop_supervised(SourceAdmission)
      next = start_supervised!({SourceAdmission, name: via(), gate: c.gate})
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(next, self())
      assert %{occupied_slots: 1, active_sources: 0} = SourceAdmission.status(next)
    after
      :sys.resume(worker)
    end

    stop_worker(c.first, worker)

    # Lost monitor ownership remains bounded debt; replacing a gate needs a separate teardown barrier.
    assert AttachmentLease.pending(c.gate) == 1
  end

  test "timed-out adoption cannot take effect later", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    {:ok, _worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    :ok = :sys.suspend(c.pool)

    try do
      assert {:error, :unavailable} = SourceAdmission.adopt(c.pool, lease)
      refute AttachmentLease.current?(lease)
      assert AttachmentLease.pending(c.gate) == 1
    after
      :sys.resume(c.pool)
    end

    _ = :sys.get_state(c.pool)
    refute AttachmentLease.current?(lease)
  end

  test "cancellation revokes authority even while the tracker is unresponsive", c do
    {:ok, lease} = SourceAdmission.reserve(c.pool, self())
    {:ok, _worker} = SourceAdmission.start_worker(c.pool, lease, c.first, worker_spec())
    :ok = SourceAdmission.adopt(c.pool, lease)
    :ok = :sys.suspend(c.pool)

    try do
      assert {:error, :unavailable} = SourceAdmission.cancel(c.pool, lease)
      refute AttachmentLease.current?(lease)
      assert AttachmentLease.pending(c.gate) == 1
    after
      :sys.resume(c.pool)
    end
  end

  defp stop_worker(supervisor, worker) do
    monitor = Process.monitor(worker)
    :ok = DynamicSupervisor.terminate_child(supervisor, worker)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :shutdown}
  end

  defp worker_spec, do: Supervisor.child_spec({Agent, fn -> :idle end}, restart: :temporary)
  defp via, do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {__MODULE__, make_ref()}}}
end
