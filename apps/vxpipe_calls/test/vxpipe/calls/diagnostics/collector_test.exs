defmodule Vxpipe.Calls.Diagnostics.CollectorTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.Calls.Diagnostics.{Collector, Supervisor}

  setup do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       clock: fn -> 0 end,
       send_after: fn _, _, _ -> make_ref() end,
       loader: fn ->
         send(parent, :loaded)
         {:ok, %{enabled: true, revision: 1}}
       end}
    )

    assert_receive :loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)

    start_supervised!(
      {Supervisor,
       name: __MODULE__.WritersRoot,
       writer_supervisor: __MODULE__.Writers,
       collector_supervisor: __MODULE__.Collectors,
       maximum_collectors: 1,
       task_supervisor: __MODULE__.Tasks}
    )

    generation = make_ref()

    options = [
      run: Vxpipe.Calls.TestLatencyRecords.run(),
      generation: generation,
      origin_us: -100_000,
      owner: self(),
      coordinator: self(),
      projection: __MODULE__.Projection,
      writer_supervisor: __MODULE__.Writers,
      writer_options: [
        repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
        task_supervisor: __MODULE__.Tasks,
        attempt_timeout_ms: 5_000
      ]
    ]

    %{options: options, generation: generation}
  end

  test "collectors start through a bounded owner and release their slot after drain", c do
    assert {:ok, collector} = Supervisor.start_collector(c.options, __MODULE__.Collectors)
    assert {:error, :max_children} = Supervisor.start_collector(c.options, __MODULE__.Collectors)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    monitor = Process.monitor(collector)
    assert :ok = Collector.close(collector, :call_ended)
    assert_receive {:DOWN, ^monitor, :process, ^collector, :normal}
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    _ = :sys.get_state(__MODULE__.Collectors)
    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
  end

  test "writes a run then revises one accepted turn as late acoustic evidence arrives", c do
    collector = start_supervised!({Collector, c.options})
    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    assert run.state == :running
    send(task, {:finish, {:ok, run}})
    assert :ok = CaptureHandoff.offer(handoff, {:provider_sample_mapping, c.generation, 0, 0})
    turn = make_ref()

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:provider_landmark, c.generation, turn, :provider_end_evidence, -30_000, 3_000}
             )

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, c.generation, turn, "turn", "command", -29_000}
             )

    assert_receive {:diagnostic_turn_write, task, scope, before}
    assert scope == {run.tenant_key, run.call_id, run.incarnation_id}
    assert before.turn_id == "turn"
    assert before.durations_us.speech_end_to_provider_end == nil
    send(task, {:finish, {:ok, before}})

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil}
             )

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 90_000, 1_000, nil}
             )

    assert_receive {:diagnostic_turn_write, task, ^scope, after_boundary}
    assert after_boundary.turn_id == before.turn_id
    assert after_boundary.revision > before.revision
    assert after_boundary.durations_us.speech_end_to_provider_end == 30_000
    send(task, {:finish, {:ok, after_boundary}})
    monitor = Process.monitor(collector)
    assert :ok = Collector.close(collector, :call_ended)
    assert_receive {:DOWN, ^monitor, :process, ^collector, :normal}
    assert_receive {:diagnostic_write, task, closed}
    assert closed.state == :closed
    assert closed.counts.observed_turns == 1
    send(task, {:finish, {:ok, closed}})
    assert {:error, :unavailable} = CaptureHandoff.offer(handoff, {:reset, 1, :audio_gap, 0})
  end

  test "capture revocation discards queued evidence and finalizes only already processed summaries",
       c do
    collector = start_supervised!({Collector, c.options})
    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    :ok = :sys.suspend(collector)

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, c.generation, make_ref(), "turn", "command", -29_000}
             )

    CaptureHandoff.close(handoff)
    monitor = Process.monitor(collector)
    :ok = :sys.resume(collector)
    assert_receive {:DOWN, ^monitor, :process, ^collector, :normal}
    assert_receive {:diagnostic_write, task, closed}
    assert closed.state == :incomplete
    assert closed.counts.observed_turns == 0
    send(task, {:finish, {:ok, closed}})
    refute_received {:diagnostic_turn_write, _, _, _}
  end
end
