defmodule Vxpipe.Calls.Diagnostics.CompositionTest do
  use ExUnit.Case, async: false

  setup do
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)
    :ok
  end

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    SourcePort,
    SourceAdmission,
    SourceSupervisor
  }

  alias Vxpipe.Calls.Diagnostics.Supervisor, as: DiagnosticsSupervisor

  setup do
    parent = self()

    options = [
      name: __MODULE__.Root,
      writer_supervisor: __MODULE__.Writers,
      collector_supervisor: __MODULE__.Collectors,
      task_supervisor: __MODULE__.Tasks,
      maximum_collectors: 1,
      repository: {Vxpipe.Calls.TestControlledLatencyRepository, self()},
      source_options: [
        name: __MODULE__.Sources,
        inference: __MODULE__.Inference,
        tasks: __MODULE__.InferenceTasks,
        runtime: __MODULE__.Runtime,
        port: __MODULE__.Port,
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

  test "configured diagnostics parent exposes its named source port without capture" do
    assert {:ok, %{maximum_sources: 1, runtime: runtime}} = SourcePort.read(__MODULE__.Port)
    assert runtime == __MODULE__.Runtime
    assert DynamicSupervisor.which_children(__MODULE__.Collectors) == []

    assert Enum.sort(Enum.map(Supervisor.which_children(__MODULE__.Sources), &elem(&1, 0))) ==
             Enum.sort([Vxpipe.CallEngine.Speech.ActivitySupervisor, SourcePort])

    refute_received :model_loaded
    refute_received {:diagnostic_write, _, _}
  end

  test "Calls subtree and root replacement retain Engine admission debt", c do
    {:ok, lease} = SourceAdmission.reserve(SourceAdmission, self(), 1)

    try do
      child_id = {SourceSupervisor, __MODULE__.Sources}
      assert :ok = Supervisor.terminate_child(c.root, child_id)
      assert {:ok, _} = Supervisor.restart_child(c.root, child_id)
      assert {:ok, _} = SourcePort.read(__MODULE__.Port)
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(SourceAdmission, self(), 1)
      stop_supervised!(DiagnosticsSupervisor)
      start_supervised!({DiagnosticsSupervisor, c.options})
      assert {:ok, _} = SourcePort.read(__MODULE__.Port)
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(SourceAdmission, self(), 1)
    after
      SourceAdmission.cancel(SourceAdmission, lease)
    end
  end

  test "destination failure replaces the port without resetting Engine admission debt", c do
    {:ok, lease} = SourceAdmission.reserve(SourceAdmission, self(), 1)

    names = [
      __MODULE__.Port,
      __MODULE__.Sources,
      __MODULE__.Tasks,
      __MODULE__.Writers,
      __MODULE__.Collectors
    ]

    old =
      Enum.map(names, fn name ->
        pid = Process.whereis(name)
        {name, pid, Process.monitor(pid)}
      end)

    try do
      Process.exit(Process.whereis(__MODULE__.Writers), :kill)

      Enum.each(old, fn {_, pid, monitor} ->
        assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      end)

      _ = Supervisor.which_children(c.root)
      assert {:ok, _} = SourcePort.read(__MODULE__.Port)
      assert {:error, :capacity_unavailable} = SourceAdmission.reserve(SourceAdmission, self(), 1)
      Enum.each(old, fn {name, pid, _} -> refute Process.whereis(name) == pid end)
    after
      SourceAdmission.cancel(SourceAdmission, lease)
    end
  end

  @tag enabled: true
  test "injected factory propagates call snapshot and pools and bounds collectors" do
    coordinator = self()
    {:ok, state} = SourcePort.read(__MODULE__.Port)
    gate = AttachmentLease.gate(1)
    {:ok, lease} = AttachmentLease.reserve(gate, coordinator)

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
      settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
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
    assert output.settings == context.settings
    assert output.owner == self()
    assert [{_, _, _, _}] = DynamicSupervisor.which_children(__MODULE__.Collectors)
    assert [{_, _, _, _}] = DynamicSupervisor.which_children(__MODULE__.Writers)
    assert_receive {:diagnostic_write, task, run}
    send(task, {:finish, {:ok, run}})
    {:ok, second_lease} = AttachmentLease.reserve(gate, coordinator)

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
