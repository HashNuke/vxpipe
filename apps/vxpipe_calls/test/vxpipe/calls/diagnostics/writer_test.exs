defmodule Vxpipe.Calls.Diagnostics.WriterTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.Diagnostics.{Handoff, Writer}

  setup do
    tasks = start_supervised!({Task.Supervisor, []})
    %{tasks: tasks}
  end

  test "blocked storage retains its reservation and cannot block or overfill producers",
       context do
    {writer, handoff} = writer(context, maximum_count: 2)
    run = run()
    assert :ok = Handoff.offer(handoff, {:run, run})
    assert_receive {:diagnostic_write, task, ^run}
    assert :ok = Handoff.offer(handoff, {:run, %{run | revision: 2}})
    assert {:error, :full} = Handoff.offer(handoff, {:run, %{run | revision: 3}})
    assert Handoff.stats(handoff).pending_count == 2
    assert Handoff.stats(handoff).pending_bytes > 0
    send(task, {:finish, {:ok, run}})
    assert_receive {:diagnostic_write, next, %{revision: 2}}
    assert Handoff.stats(handoff).pending_count == 1
    send(next, {:finish, {:ok, %{run | revision: 2}}})
    assert_receive {:diagnostic_settled, ^writer, :stored}
  end

  test "byte capacity includes in-flight work and invalid payloads never enter the queue",
       context do
    {_writer, handoff} = writer(context, maximum_count: 100, maximum_bytes: 1)
    assert {:error, :full} = Handoff.offer(handoff, {:run, run()})
    assert {:error, :invalid_write} = Handoff.offer(handoff, {:run, %{audio: <<0, 1>>}})
    assert Handoff.stats(handoff).pending_count == 0
    assert Handoff.stats(handoff).pending_bytes == 0
  end

  test "retry preserves the original count and byte reservation", context do
    {writer, handoff} = writer(context, maximum_count: 1, retry_delay_ms: 1)
    run = run()
    assert :ok = Handoff.offer(handoff, {:run, run})
    assert_receive {:diagnostic_write, first, ^run}
    bytes = Handoff.stats(handoff).pending_bytes
    send(first, {:finish, {:error, :diagnostics_unavailable}})
    assert_receive {:diagnostic_write, retry, ^run}
    assert Handoff.stats(handoff).pending_count == 1
    assert Handoff.stats(handoff).pending_bytes == bytes
    assert {:error, :full} = Handoff.offer(handoff, {:run, run})
    send(retry, {:finish, {:ok, run}})
    assert_receive {:diagnostic_settled, ^writer, :stored}
    assert Handoff.stats(handoff).pending_count == 0
  end

  test "timeouts and exhausted retries discard diagnostics and release capacity", context do
    {writer, handoff} = writer(context, attempt_timeout_ms: 20, maximum_attempts: 1)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    # Admission is included in the deadline, so under load it may expire before
    # the repository is invoked. Either path must settle and free the reservation.
    assert_receive {:diagnostic_settled, ^writer, :discarded}, 1_000
    assert Handoff.stats(handoff).pending_count == 0
    assert Handoff.stats(handoff).pending_bytes == 0
    assert Handoff.stats(handoff).discarded == 1
  end

  test "closing rejects new work and drains already accepted summaries", context do
    {writer, handoff} = writer(context)
    run = run()
    assert :ok = Handoff.offer(handoff, {:run, run})
    assert_receive {:diagnostic_write, task, ^run}
    monitor = Process.monitor(writer)
    assert :ok = Writer.drain(writer)
    assert {:error, :unavailable} = Handoff.offer(handoff, {:run, run})
    send(task, {:finish, {:ok, run}})
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
    assert Handoff.stats(handoff).pending_count == 0
  end

  test "drain deadline cancels in-flight work and discards queued summaries", context do
    {writer, handoff} = writer(context, drain_timeout_ms: 20)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    assert_receive {:diagnostic_write, task, _run}
    assert :ok = Handoff.offer(handoff, {:run, run()})
    writer_monitor = Process.monitor(writer)
    task_monitor = Process.monitor(task)
    assert :ok = Writer.drain(writer)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :normal}
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}
    assert Handoff.stats(handoff).pending_count == 0
    assert Handoff.stats(handoff).discarded == 2
  end

  test "abrupt writer death cannot orphan a blocked database task", context do
    {writer, handoff} = writer(context)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    assert_receive {:diagnostic_write, task, _run}
    task_monitor = Process.monitor(task)
    writer_monitor = Process.monitor(writer)
    Process.exit(writer, :kill)
    assert_receive {:DOWN, ^writer_monitor, :process, ^writer, :killed}
    assert_receive {:DOWN, ^task_monitor, :process, ^task, _reason}
    assert {:error, :unavailable} = Handoff.offer(handoff, {:run, run()})
  end

  test "concurrent producers cannot exceed count or byte reservations", context do
    {writer, handoff} =
      writer(context, maximum_count: 8, maximum_bytes: 40_000, drain_timeout_ms: 20)

    outcomes =
      1..64
      |> Task.async_stream(fn _ -> Handoff.offer(handoff, {:run, run()}) end,
        max_concurrency: 32,
        timeout: 1_000
      )
      |> Enum.to_list()

    admitted = Enum.count(outcomes, &(&1 == {:ok, :ok}))
    stats = Handoff.stats(handoff)
    assert admitted > 0 and admitted <= 8
    assert stats.pending_count == admitted
    assert stats.pending_bytes <= 40_000
    monitor = Process.monitor(writer)
    Writer.drain(writer)
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
    assert Handoff.stats(handoff).pending_bytes == 0
  end

  test "task failure consumes bounded attempts without failing the writer", context do
    {writer, handoff} = writer(context, maximum_attempts: 1)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    assert_receive {:diagnostic_write, task, _run}
    Process.exit(task, :kill)
    assert_receive {:diagnostic_settled, ^writer, :discarded}
    assert Writer.handoff(writer) == handoff
    assert Handoff.stats(handoff).pending_count == 0
  end

  test "shared task capacity exhaustion drops diagnostics without crashing the writer", context do
    limited =
      start_supervised!(
        Supervisor.child_spec({Task.Supervisor, max_children: 1}, id: :limited_tasks)
      )

    {:ok, blocked} = Task.Supervisor.start_child(limited, fn -> receive do: (:finish -> :ok) end)
    {writer, handoff} = writer(context, task_supervisor: limited, maximum_attempts: 1)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    assert_receive {:diagnostic_settled, ^writer, :discarded}
    assert Writer.handoff(writer) == handoff
    send(blocked, :finish)
  end

  test "an unexpected success payload cannot claim that the queued record was stored", context do
    {writer, handoff} = writer(context, maximum_attempts: 1)
    assert :ok = Handoff.offer(handoff, {:run, run()})
    assert_receive {:diagnostic_write, task, _run}
    send(task, {:finish, {:ok, :wrong_record}})
    assert_receive {:diagnostic_settled, ^writer, :discarded}
    assert Handoff.stats(handoff).discarded == 1
  end

  test "retained binary backing storage is copied or charged before admission", context do
    {_writer, handoff} = writer(context, maximum_bytes: 1_048_576)
    backing = :binary.copy("r", 8_388_608)
    record = %{run() | id: binary_part(backing, 0, 128)}
    assert :binary.referenced_byte_size(record.id) == byte_size(backing)

    case Handoff.offer(handoff, {:run, record}) do
      {:error, :full} ->
        :ok

      :ok ->
        assert_receive {:diagnostic_write, task, admitted}

        assert :binary.referenced_byte_size(admitted.id) <=
                 Handoff.stats(handoff).pending_bytes

        send(task, {:finish, {:ok, admitted}})
    end
  end

  test "an unresponsive task supervisor cannot prevent the bounded writer drain", context do
    {writer, handoff} =
      writer(context, maximum_attempts: 1, attempt_timeout_ms: 20, drain_timeout_ms: 20)

    tasks = context.tasks
    :ok = :sys.suspend(tasks)

    try do
      assert :ok = Handoff.offer(handoff, {:run, run()})

      assert Writer.handoff(writer) == handoff

      monitor = Process.monitor(writer)
      assert :ok = Writer.drain(writer)
      assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}, 200
    after
      :sys.resume(tasks)
    end

    _ = :sys.get_state(tasks)
    refute_receive {:diagnostic_write, _task, _record}
  end

  test "expired admission requests cannot accumulate outside the retained-write budget",
       context do
    {writer, handoff} =
      writer(context, maximum_count: 1, maximum_attempts: 1, attempt_timeout_ms: 10)

    tasks = context.tasks
    :ok = :sys.suspend(tasks)

    try do
      for revision <- 1..5 do
        case Handoff.offer(handoff, {:run, %{run() | revision: revision}}) do
          :ok -> assert_receive {:diagnostic_settled, ^writer, :discarded}
          {:error, reason} -> assert reason in [:full, :unavailable]
        end
      end

      {:message_queue_len, queued_admissions} = Process.info(tasks, :message_queue_len)
      assert queued_admissions <= 1
    after
      :sys.resume(tasks)
    end
  end

  defp writer(context, options \\ []) do
    writer =
      start_supervised!(
        {Writer,
         Keyword.merge(
           [
             repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
             task_supervisor: context.tasks,
             observer: self(),
             attempt_timeout_ms: 1_000,
             maximum_attempts: 2,
             drain_timeout_ms: 1_000
           ],
           options
         )}
      )

    {writer, Writer.handoff(writer)}
  end

  defp run, do: Vxpipe.Calls.TestLatencyRecords.run()
end
