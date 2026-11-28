defmodule Vxpipe.CallEngine.Speech.Silero.PoolDispatchTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.{Batch, Pool, PoolSupervisor}

  setup do
    parent = self()

    run = fn :model, rows ->
      send(parent, {:batch, self(), length(rows)})

      receive do
        :finish -> {:ok, Enum.map(rows, fn {_pcm, state} -> {0.5, state} end)}
        :bad_shape -> {:ok, []}
      end
    end

    start_supervised!(
      {PoolSupervisor,
       name: __MODULE__.Supervisor,
       dispatcher: __MODULE__,
       workers_name: __MODULE__.Workers,
       run: run,
       budget_options: [linux?: false, logical_processors: 1]}
    )

    :ok
  end

  test "dispatches a singleton immediately, then batches queued owners in order" do
    first = submit()
    assert_receive {:batch, worker, 1}
    queued = for _ <- 1..3, do: submit()
    send(worker, :finish)
    assert_result(first)
    assert_receive {:batch, ^worker, 3}
    send(worker, :finish)
    Enum.each(queued, &assert_result/1)
  end

  test "reports queue and native timing and a fixed per-row outcome" do
    events = for suffix <- [:dispatch, :batch, :outcome], do: [:vxpipe, :silero, :pool, suffix]
    id = make_ref()
    :ok = :telemetry.attach_many(id, events, &__MODULE__.observe/4, self())
    on_exit(fn -> :telemetry.detach(id) end)
    first = submit()
    assert_receive {:batch, worker, 1}
    send(worker, :finish)
    assert_result(first)
    assert_receive {:dispatch, %{rows: 1, queue_duration: elapsed}, %{}}
    assert elapsed >= 0
    assert_receive {:batch, %{rows: 1, duration: duration}, %{}}
    assert duration >= 0
    assert_receive {:outcome, %{count: 1}, %{outcome: :ok}}
  end

  def observe(event, measurements, metadata, target),
    do: send(target, {List.last(event), measurements, metadata})

  test "retiring a running allocation retains physical credit until completion" do
    {lease, ref} = submit()
    assert_receive {:batch, worker, 1}
    assert :ok = Pool.close(lease)
    assert %{retired: 1, admitted: 1} = Pool.status(__MODULE__)
    send(worker, :finish)
    # A completed subsequent batch acknowledges settlement of the retired row.
    live = submit()
    assert_receive {:batch, ^worker, 1}
    send(worker, :finish)
    assert_result(live)
    assert %{retired: 0, admitted: 1} = Pool.status(__MODULE__)
    refute_received {:silero_result, ^ref, _}
  end

  test "a stalled dispatcher bounds submission time and admits only one pending row per lease" do
    {:ok, lease} =
      Pool.reserve(make_ref(), System.monotonic_time(:millisecond) + 5000, __MODULE__)

    :sys.suspend(lease.pool)

    try do
      row = {:binary.copy(<<0>>, 1024), Batch.initial_state()}

      assert {:error, :classification_timeout} =
               Pool.submit(lease, 0, :model, row, System.monotonic_time(:millisecond) + 20)

      assert {:error, :busy} =
               Pool.submit(lease, 0, :model, row, System.monotonic_time(:millisecond) + 20)
    after
      :sys.resume(lease.pool)
    end

    assert %{ready: 0, in_flight: 0} = Pool.status(__MODULE__)
  end

  test "cancelling one live batch row preserves neighbors, FIFO order and the cap of sixteen" do
    first = submit()
    assert_receive {:batch, worker, 1}
    [{lease, ref} | neighbors] = for _ <- 1..17, do: submit()
    send(worker, :finish)
    assert_result(first)
    assert_receive {:batch, ^worker, 16}
    assert {:error, :unknown_job} = Task.async(fn -> Pool.cancel(lease, ref) end) |> Task.await()
    assert :ok = Pool.cancel(lease, ref)
    assert %{ready: 1, in_flight: 16, retired: 1} = Pool.status(__MODULE__)
    send(worker, :finish)
    assert_receive {:silero_retired, ^ref}
    Enum.each(Enum.take(neighbors, 15), &assert_result/1)
    assert_receive {:batch, ^worker, 1}
    send(worker, :finish)
    assert_result(List.last(neighbors))
    refute_received {:silero_result, ^ref, _}
  end

  test "recovers after a worker exit and fails malformed results once" do
    {_lease, ref} = submit()
    assert_receive {:batch, worker, 1}
    Process.exit(worker, :kill)
    assert_receive {:silero_result, ^ref, {:error, :classification_failed}}
    {_lease, next} = submit()
    assert_receive {:batch, replacement, 1}
    refute replacement == worker
    send(replacement, :bad_shape)
    assert_receive {:silero_result, ^next, {:error, :classification_failed}}
    live = submit()
    assert_receive {:batch, ^replacement, 1}
    send(replacement, :finish)
    assert_result(live)
    refute_received {:silero_result, ^ref, _}
    refute_received {:silero_result, ^next, _}
  end

  test "an unloaded model cannot claim or dispatch a row" do
    deadline = System.monotonic_time(:millisecond) + 5000
    {:ok, lease} = Pool.reserve(make_ref(), deadline, __MODULE__)
    row = {:binary.copy(<<0>>, 1024), Batch.initial_state()}

    assert {:error, :invalid_row} = Pool.submit(lease, 0, nil, row, deadline)
    assert %{in_flight: 0, ready: 0} = Pool.status(lease.pool)
  end

  test "an expired cancellation cannot block the owner or enqueue retries" do
    {lease, ref} = submit(150)
    assert_receive {:batch, worker, 1}
    :sys.suspend(lease.pool)

    try do
      started = System.monotonic_time(:millisecond)
      assert {:error, :unknown_job} = Pool.cancel(lease, ref)
      assert System.monotonic_time(:millisecond) - started < 1000

      for _ <- 1..12, do: assert({:error, :unknown_job} = Pool.cancel(lease, ref))
      {:messages, messages} = Process.info(lease.pool, :messages)
      assert Enum.count(messages, &match?({:"$gen_call", _, {:cancel, _, _}}, &1)) <= 1
    after
      :sys.resume(lease.pool)
      send(worker, :finish)
    end
  end

  test "a running deadline expires before the worker releases its physical credit" do
    {lease, ref} = submit(150)
    assert_receive {:batch, worker, 1}

    assert_receive {:silero_result, ^ref, {:error, :classification_timeout, :await_settlement}},
                   1000

    assert %{retired: 1, in_flight: 1} = Pool.status(lease.pool)
    refute_received {:silero_retired, ^ref}
    send(worker, :finish)
    assert_receive {:silero_retired, ^ref}
    assert %{retired: 0, in_flight: 0} = Pool.status(lease.pool)
  end

  test "queued cancellation and allocation closure release their reservation" do
    first = submit()
    assert_receive {:batch, worker, 1}
    {lease, ref} = submit()
    assert :ok = Pool.cancel(lease, ref)
    assert_receive {:silero_retired, ^ref}
    assert :ok = Pool.close(lease)
    assert %{ready: 0, admitted: 1} = Pool.status(__MODULE__)
    send(worker, :finish)
    assert_result(first)
    refute_received {:batch, ^worker, _}
  end

  test "dispatcher replacement fences old leases and starts fresh workers" do
    {lease, ref} = submit()
    assert_receive {:batch, old_worker, 1}
    monitor = Process.monitor(old_worker)
    Process.exit(lease.pool, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^old_worker, _}, 6000
    _ = Supervisor.which_children(__MODULE__.Supervisor)
    assert {:error, :unknown_lease} = Pool.close(lease)
    next = submit()
    assert_receive {:batch, new_worker, 1}
    refute new_worker == old_worker
    send(new_worker, :finish)
    assert_result(next)
    refute_received {:silero_result, ^ref, _}
  end

  defp submit(timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    {:ok, lease} = Pool.reserve(make_ref(), deadline, __MODULE__)

    {:ok, ref} =
      Pool.submit(
        lease,
        {:epoch, 0},
        :model,
        {:binary.copy(<<0>>, 1024), Batch.initial_state()},
        deadline
      )

    {lease, ref}
  end

  defp assert_result({_lease, ref}) do
    assert_receive {:silero_result, ^ref, {:ok, 0.5, _packed}}
  end
end
