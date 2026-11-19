defmodule Vxpipe.Calls.Diagnostics.CompositionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    SourceCoordinator,
    SourceSupervisor,
    SettingsSupervisor
  }

  alias Vxpipe.Calls.Diagnostics.Supervisor, as: DiagnosticsSupervisor

  setup test_context do
    parent = self()

    start_supervised!(
      {SettingsSupervisor,
       name: __MODULE__.Settings,
       projection: __MODULE__.Projection,
       reader: __MODULE__.Reader,
       loader: fn ->
         send(parent, :settings_loaded)
         {:ok, %{enabled: Map.get(test_context, :enabled, false), revision: 1}}
       end}
    )

    assert_receive :settings_loaded
    _ = :sys.get_state(__MODULE__.Reader)
    _ = :sys.get_state(__MODULE__.Projection)

    options = [
      name: __MODULE__.Root,
      writer_supervisor: __MODULE__.Writers,
      collector_supervisor: __MODULE__.Collectors,
      task_supervisor: __MODULE__.Tasks,
      maximum_collectors: 1,
      projection: __MODULE__.Projection,
      repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
      source_options: [
        name: __MODULE__.Sources,
        workers: __MODULE__.SourceWorkers,
        inference: __MODULE__.Inference,
        tasks: __MODULE__.InferenceTasks,
        runtime: __MODULE__.Runtime,
        coordinator: __MODULE__.Coordinator,
        load: fn ->
          send(parent, :model_loaded)
          {:ok, :model}
        end
      ]
    ]

    specs = Vxpipe.Calls.Application.child_specs(diagnostics: options)

    [{DiagnosticsSupervisor, configured}] =
      Enum.filter(specs, &match?({DiagnosticsSupervisor, _}, &1))

    root = start_supervised!({DiagnosticsSupervisor, configured})
    %{root: root, options: options}
  end

  test "configured diagnostics parent starts its source coordinator without enabling capture" do
    assert %{active_sources: 0, pending?: false, last_reason: :settings_unavailable} =
             SourceCoordinator.status(__MODULE__.Coordinator)

    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []
    assert DynamicSupervisor.which_children(__MODULE__.SourceWorkers) == []
    refute_received :model_loaded
    refute_received {:diagnostic_write, _, _}
  end

  test "source subtree restart preserves parent admission reservations", c do
    initial = :sys.get_state(__MODULE__.Coordinator)
    {:ok, lease} = AttachmentLease.reserve(initial.attachment_gate, self())
    assert AttachmentLease.pending(initial.attachment_gate) == 1
    child_id = {SourceSupervisor, __MODULE__.Sources}
    assert :ok = Supervisor.terminate_child(c.root, child_id)
    assert {:ok, _} = Supervisor.restart_child(c.root, child_id)
    restarted = :sys.get_state(__MODULE__.Coordinator)
    assert restarted.attachment_gate == initial.attachment_gate
    assert {:error, :unavailable} = AttachmentLease.reserve(restarted.attachment_gate, self())

    stop_supervised!(DiagnosticsSupervisor)
    start_supervised!({DiagnosticsSupervisor, c.options})
    replaced = :sys.get_state(__MODULE__.Coordinator)
    refute replaced.attachment_gate == initial.attachment_gate
    assert AttachmentLease.pending(replaced.attachment_gate) == 0
    AttachmentLease.cancel(lease)
    AttachmentLease.finish(lease)
  end

  test "abrupt destination failure restarts every destination without resetting admission debt",
       c do
    initial = :sys.get_state(__MODULE__.Coordinator)
    {:ok, lease} = AttachmentLease.reserve(initial.attachment_gate, self())
    names = [__MODULE__.Sources, __MODULE__.Tasks, __MODULE__.Writers, __MODULE__.Collectors]

    old =
      Enum.map(names, fn name ->
        pid = Process.whereis(name)
        {name, pid, Process.monitor(pid)}
      end)

    Process.exit(Process.whereis(__MODULE__.Writers), :kill)

    Enum.each(old, fn {_name, pid, monitor} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
    end)

    _ = Supervisor.which_children(c.root)
    restarted = :sys.get_state(__MODULE__.Coordinator)
    assert restarted.attachment_gate == initial.attachment_gate
    assert {:error, :unavailable} = AttachmentLease.reserve(restarted.attachment_gate, self())
    Enum.each(old, fn {name, pid, _monitor} -> refute Process.whereis(name) == pid end)
    AttachmentLease.cancel(lease)
    AttachmentLease.finish(lease)
  end

  @tag enabled: true
  test "injected factory propagates parent projection and pools and bounds collectors" do
    coordinator = Process.whereis(__MODULE__.Coordinator)
    state = :sys.get_state(coordinator)
    {:ok, lease} = AttachmentLease.reserve(state.attachment_gate, coordinator)

    context = %{
      attachment_lease: lease,
      identity: %{
        tenant_id: "tenant",
        call_id: "call",
        room_id: "room",
        incarnation_id: "incarnation"
      },
      participant_id: "human",
      connection_id: "connection",
      capability: self(),
      coordinator: coordinator,
      generation: make_ref(),
      provider_generation: make_ref(),
      settings_revision: 1,
      source_epoch: make_ref(),
      source_id: "source",
      clock_id: "clock",
      run_id: "run",
      origin_us: System.monotonic_time(:microsecond),
      anchor_utc: DateTime.utc_now(),
      mode: :benchmark_only,
      provider_profile: %{
        missing: [],
        acknowledged: %{
          "model_id" => "scribe_v2_realtime",
          "sample_rate" => 16_000,
          "audio_format" => "pcm_16000",
          "commit_strategy" => "vad",
          "vad_silence_threshold_secs" => 1.5,
          "vad_threshold" => 0.4,
          "min_speech_duration_ms" => 100,
          "min_silence_duration_ms" => 100,
          "keepalive_interval_ms" => 500
        }
      }
    }

    assert {:ok, output} = state.collector.(context)
    assert AttachmentLease.adopt(lease)
    AttachmentLease.finish(lease)
    assert output.projection == __MODULE__.Projection
    assert output.owner == self()
    assert [{_, _, _, _}] = DynamicSupervisor.which_children(__MODULE__.Collectors)
    assert [{_, _, _, _}] = DynamicSupervisor.which_children(__MODULE__.Writers)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    {:ok, second_lease} = AttachmentLease.reserve(state.attachment_gate, coordinator)

    assert {:error, :unavailable} =
             state.collector.(%{context | attachment_lease: second_lease, run_id: "second"})

    AttachmentLease.cancel(second_lease)
    AttachmentLease.finish(second_lease)
    monitor = Process.monitor(output.receiver)
    assert :ok = Vxpipe.Calls.Diagnostics.Collector.close(output.receiver, :call_ended)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1_000
    assert_receive {:diagnostic_write, task, closed}
    assert closed.state == :closed
    send(task, {:finish, {:ok, closed}})
    refute_received :model_loaded
  end
end
