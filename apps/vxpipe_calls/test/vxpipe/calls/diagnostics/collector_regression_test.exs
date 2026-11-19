defmodule Vxpipe.Calls.Diagnostics.CollectorRegressionTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.{CaptureHandoff, SettingsSupervisor}
  alias Vxpipe.Calls.Diagnostics.{Collector, Coverage, Supervisor}

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
        observer: self(),
        maximum_attempts: 1,
        attempt_timeout_ms: 5_000
      ]
    ]

    %{options: options, generation: generation}
  end

  test "a lost revision during drain must not claim complete coverage", c do
    collector = start_supervised!({Collector, c.options})
    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    turn = make_ref()

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, c.generation, turn, "turn", "command", -29_000}
             )

    assert_receive {:diagnostic_turn_write, task, _scope, revision1}
    send(task, {:finish, {:ok, revision1}})
    assert_receive {:diagnostic_settled, _, :stored}
    assert_receive {:diagnostic_settled, _, :stored}

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:response_landmark, "turn", "command", "response", :first_response_text, -28_000}
             )

    assert_receive {:diagnostic_turn_write, task, _scope, revision2}
    assert revision2.revision > revision1.revision
    assert :ok = Collector.close(collector, :call_ended)
    send(task, {:finish, {:error, :diagnostics_unavailable}})
    assert_receive {:diagnostic_settled, _, :discarded}
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    assert Coverage.describe(closed, 1, closed.heartbeat_at).status == :incomplete
  end

  test "retained source run metadata copies large backing binaries", c do
    backing = :binary.copy("r", 8_388_608)
    run = %{Keyword.fetch!(c.options, :run) | id: binary_part(backing, 0, 128)}
    assert :binary.referenced_byte_size(run.id) == byte_size(backing)
    collector = start_supervised!({Collector, Keyword.put(c.options, :run, run)})
    retained = :sys.get_state(collector).run.id
    assert :binary.referenced_byte_size(retained) <= 256
  end

  test "an observed audio gap must not claim complete capture", c do
    collector = start_supervised!({Collector, c.options})
    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    assert :ok = CaptureHandoff.offer(handoff, {:reset, 1, :audio_gap, -10_000})
    _ = :sys.get_state(collector)
    assert :ok = Collector.close(collector, :call_ended)
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    assert Coverage.describe(closed, 0, closed.heartbeat_at).status == :incomplete
  end

  test "unmatched provider evidence remains visible in terminal coverage", c do
    collector = start_supervised!({Collector, c.options})
    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:provider_landmark, c.generation, make_ref(), :provider_end_evidence, -30_000,
                3_000}
             )

    _ = :sys.get_state(collector)
    assert :ok = Collector.close(collector, :call_ended)
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    assert closed.counts.unmatched_provider_events == 1
    assert Coverage.describe(closed, 0, closed.heartbeat_at).status == :incomplete
  end

  test "observed turn count includes a row rejected by full storage admission", c do
    writer_options = Keyword.put(Keyword.fetch!(c.options, :writer_options), :maximum_count, 1)

    collector =
      start_supervised!({Collector, Keyword.put(c.options, :writer_options, writer_options)})

    handoff = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}

    assert :ok =
             CaptureHandoff.offer(
               handoff,
               {:room_turn_completed, c.generation, make_ref(), "turn", "command", -29_000}
             )

    _ = :sys.get_state(collector)
    send(task, {:finish, {:ok, run}})
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    assert closed.counts.observed_turns == 1
    assert :storage_loss in closed.reasons
  end

  test "terminal coverage waits for the writer settlement acknowledgment", c do
    collector = start_supervised!({Collector, c.options})
    capture = Collector.handoff(collector)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    assert_receive {:diagnostic_settled, writer, :stored}
    # Delay only the settlement notification at the project-owned writer boundary.
    parent = self()
    :sys.replace_state(writer, &%{&1 | observer: parent})

    assert :ok =
             CaptureHandoff.offer(
               capture,
               {:room_turn_completed, c.generation, make_ref(), "turn", "command", -29_000}
             )

    assert_receive {:diagnostic_turn_write, task, _, _}
    send(task, {:finish, {:error, :diagnostics_unavailable}})
    assert_receive {:diagnostic_settled, ^writer, :discarded} = settlement
    monitor = Process.monitor(collector)
    assert :ok = Collector.close(collector, :call_ended)
    refute_receive {:DOWN, ^monitor, :process, ^collector, _}, 30
    send(collector, settlement)
    assert_receive {:DOWN, ^monitor, :process, ^collector, :normal}
    assert_receive {:diagnostic_write, task, closed}
    send(task, {:finish, {:ok, closed}})
    assert Coverage.describe(closed, 0, closed.heartbeat_at).status == :incomplete
  end
end
