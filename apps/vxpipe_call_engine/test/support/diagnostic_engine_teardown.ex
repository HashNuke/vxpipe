defmodule Vxpipe.CallEngine.DiagnosticEngineTeardown do
  @moduledoc false
  import ExUnit.Assertions
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SourceAdmission,
    SourceWorker
  }

  alias Vxpipe.CallEngine.Diagnostics.RoomSupervisor, as: DiagnosticSupervisor

  def verify(settings) do
    {:ok, _} = Application.ensure_all_started(:ex_unit)
    Application.put_env(:vxpipe_call_engine, CallEngine.Application, settings)
    {:ok, _} = Application.ensure_all_started(:vxpipe_call_engine)
    Vxpipe.CallEngine.TestCallSettings.start!(__MODULE__)

    {:ok, fixtures} =
      Supervisor.start_link(
        [
          {CallEngine.Speech.ActivitySupervisor,
           name: __MODULE__.Activity,
           tasks: __MODULE__.Inference,
           runtime: __MODULE__.Runtime,
           diagnostic_capacity: 1,
           load: fn -> {:ok, :synthetic} end,
           classify: fn _, stream, _ -> {:ok, stream, []} end},
          {Task.Supervisor, name: __MODULE__.Tasks}
        ],
        strategy: :one_for_one,
        name: __MODULE__.Fixtures
      )

    try do
      run()
    after
      Supervisor.stop(fixtures)
      Application.stop(:vxpipe_call_engine)
    end
  end

  defp run do
    plan = plan()
    assert {:ok, room} = CallEngine.start_call(plan)

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id
    }

    workers = DiagnosticSupervisor.address(identity, :workers)
    service = GenServer.whereis(DiagnosticSupervisor.address(identity, :service))
    runner = GenServer.whereis(DiagnosticSupervisor.address(identity, :runner))
    assert is_pid(service) and is_pid(runner)
    root = Process.whereis(CallEngine.Supervisor)
    root_down = Process.monitor(root)
    gate = :sys.get_state(SourceAdmission).gate

    active =
      for mode <- [:operational_reuse, :benchmark_only] do
        {:ok, lease} = SourceAdmission.reserve(SourceAdmission, service)
        options = worker_options(mode, lease)

        assert {:ok, worker} =
                 SourceAdmission.start_worker(
                   SourceAdmission,
                   lease,
                   workers,
                   {SourceWorker, options}
                 )

        assert :ok = SourceAdmission.adopt(SourceAdmission, lease)
        {worker, Process.monitor(worker), SourceWorker.handoff(worker)}
      end

    admitted = MapSet.new(active, fn {worker, _, _} -> worker end)

    actual =
      workers |> DynamicSupervisor.which_children() |> MapSet.new(fn {_, pid, _, _} -> pid end)

    assert actual == admitted

    {:ok, pending_lease} = SourceAdmission.reserve(SourceAdmission, service)
    options = worker_options(:operational_reuse, pending_lease)
    parent = self()

    spec = %{
      id: :pending_worker,
      restart: :temporary,
      start: {CallEngine.DiagnosticBlockedWorkerStart, :start_link, [options, parent]}
    }

    # Execute the start in the actual room-owned IO runner. Its unreturned
    # DynamicSupervisor start is the shutdown boundary under test.
    pending =
      Task.Supervisor.async_nolink(__MODULE__.Tasks, fn ->
        :sys.replace_state(runner, fn state ->
          SourceAdmission.start_worker(SourceAdmission, pending_lease, workers, spec)
          state
        end)
      end)

    assert_receive {:unresolved_worker_start, starting_supervisor, result}, 2_000

    try do
      assert {:ok, pending_worker} = result
      assert starting_supervisor == GenServer.whereis(workers)
      pending_down = Process.monitor(pending_worker)
      runner_down = Process.monitor(runner)
      assert AttachmentLease.pending(gate) == 3

      stop =
        Task.Supervisor.async_nolink(__MODULE__.Tasks, fn ->
          assert :ok = Application.stop(:vxpipe_call_engine)

          for pid <- [pending_worker | Enum.map(active, fn {pid, _, _} -> pid end)] do
            monitor = Process.monitor(pid)
            assert_receive {:DOWN, ^monitor, :process, ^pid, :noproc}, 1_000
          end

          :ok
        end)

      assert_receive {:DOWN, ^runner_down, :process, ^runner, :killed}, 2_000
      assert Task.yield(stop, 0) == nil
      refute_received {:DOWN, ^root_down, :process, ^root, _}
      assert AttachmentLease.pending(gate) > 0

      restart =
        Task.Supervisor.async_nolink(__MODULE__.Tasks, fn ->
          send(parent, :restart_requested)
          Application.ensure_all_started(:vxpipe_call_engine)
        end)

      assert_receive :restart_requested
      assert Task.yield(restart, 0) == nil
      assert :sys.get_state(SourceAdmission).gate.counter == gate.counter

      send(starting_supervisor, :release_worker_start)
      assert {:ok, :ok} = Task.yield(stop, 5_000)
      assert_receive {:DOWN, ^root_down, :process, ^root, _}, 1_000
      assert_receive {:DOWN, ^pending_down, :process, ^pending_worker, _}, 1_000
      assert {:exit, _} = Task.yield(pending, 1_000)

      for {worker, monitor, handoff} <- active do
        assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
        refute CaptureHandoff.current?(handoff)
      end

      refute AttachmentLease.current?(pending_lease)
      assert {:ok, {:ok, _}} = Task.yield(restart, 5_000)
      fresh = :sys.get_state(SourceAdmission).gate
      refute fresh.counter == gate.counter
      assert AttachmentLease.pending(fresh) == 0
      assert {:ok, next} = SourceAdmission.reserve(SourceAdmission, self())
      assert :ok = SourceAdmission.cancel(SourceAdmission, next)
      %{retired_workers: 3, fresh_gate: true}
    after
      send(starting_supervisor, :release_worker_start)
    end
  end

  defp worker_options(mode, lease) do
    {:ok, output} =
      CaptureHandoff.new(self(), settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__))

    [
      owner: self(),
      output: output,
      settings: Vxpipe.CallEngine.TestCallSettings.get(__MODULE__),
      coordinator: self(),
      attachment_lease: lease,
      mode: mode,
      admission:
        if(mode == :benchmark_only,
          do: CallEngine.Speech.ActivityRuntime.diagnostic_admission(__MODULE__.Runtime)
        ),
      source_epoch: make_ref(),
      clock_id: "clock",
      source_id: "source",
      origin_us: System.monotonic_time(:microsecond)
    ]
  end

  defp plan do
    alias Vxpipe.CallEngine.{CallSpec, CallInvocation, CallSpecCompiler}

    {:ok, spec} =
      CallSpec.new(
        %{
          schema_version: "20260915.01",
          entry_caller: "caller",
          entry_receiver: "receiver",
          defaults: %{capabilities: %{}},
          participants:
            Map.new(["caller", "receiver"], fn name ->
              {name,
               %{
                 type: "human",
                 connection: %{service: "web", mode: "receive", admission: "start_call"}
               }}
            end)
        },
        resource_id: "teardown",
        revision: 1
      )

    {:ok, invocation} =
      CallInvocation.new(
        %{
          call_spec: %{id: "teardown", revision: 1},
          initial_variables: %{},
          transport: %{type: "web"}
        },
        tenant_id: "tenant",
        actor_id: "actor",
        call_id: "teardown-call",
        room_id: "teardown-room"
      )

    {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
