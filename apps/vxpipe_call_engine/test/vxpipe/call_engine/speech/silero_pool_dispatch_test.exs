defmodule Vxpipe.CallEngine.Speech.Silero.PoolDispatchTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Silero.{Batch, Pool, PoolSupervisor}

  setup do
    parent = self()

    run = fn :model, rows ->
      send(parent, {:batch, self(), length(rows)})

      receive do
        :finish -> {:ok, Enum.map(rows, fn {_pcm, state} -> {0.5, state} end)}
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

  defp submit do
    deadline = System.monotonic_time(:millisecond) + 5000
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
