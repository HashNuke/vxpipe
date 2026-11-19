defmodule Vxpipe.Calls.Diagnostics.SupervisorTest do
  use ExUnit.Case, async: false
  alias Vxpipe.Calls.Diagnostics.{Handoff, Supervisor, Writer}

  test "diagnostic writers start through their bounded owner and do not restart after drain" do
    supervisor =
      start_supervised!(
        {Supervisor,
         name: __MODULE__.Root,
         task_supervisor: __MODULE__.Tasks,
         writer_supervisor: __MODULE__.Writers,
         maximum_writers: 1}
      )

    options = [
      repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
      task_supervisor: __MODULE__.Tasks
    ]

    assert {:ok, writer} = Supervisor.start_writer(options, __MODULE__.Writers)
    assert {:error, :max_children} = Supervisor.start_writer(options, __MODULE__.Writers)
    monitor = Process.monitor(writer)
    assert :ok = Writer.drain(writer)
    assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
    assert DynamicSupervisor.which_children(__MODULE__.Writers) == []
    assert length(Elixir.Supervisor.which_children(supervisor)) == 3
  end

  test "unresolved admission remains bounded across replacement writers" do
    start_supervised!(
      {Supervisor,
       name: __MODULE__.Root,
       task_supervisor: __MODULE__.Tasks,
       writer_supervisor: __MODULE__.Writers,
       maximum_writers: 1}
    )

    tasks = Process.whereis(__MODULE__.Tasks)
    :ok = :sys.suspend(tasks)

    options = [
      repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
      task_supervisor: __MODULE__.Tasks,
      observer: self(),
      maximum_attempts: 1,
      attempt_timeout_ms: 10
    ]

    try do
      for _ <- 1..5 do
        {:ok, writer} = Supervisor.start_writer(options, __MODULE__.Writers)
        handoff = Writer.handoff(writer)
        assert :ok = Handoff.offer(handoff, {:run, Vxpipe.Calls.TestLatencyRecords.run()})
        assert_receive {:diagnostic_settled, ^writer, :discarded}
        monitor = Process.monitor(writer)
        assert :ok = Writer.drain(writer)
        assert_receive {:DOWN, ^monitor, :process, ^writer, :normal}
        _ = :sys.get_state(__MODULE__.Writers)
      end

      assert {:message_queue_len, count} = Process.info(tasks, :message_queue_len)
      assert count <= 1
    after
      :sys.resume(tasks)
    end

    _ = :sys.get_state(tasks)
    refute_receive {:diagnostic_write, _task, _record}
  end
end
