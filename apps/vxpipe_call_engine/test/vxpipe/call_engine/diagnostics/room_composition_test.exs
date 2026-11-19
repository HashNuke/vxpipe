defmodule Vxpipe.CallEngine.Diagnostics.RoomCompositionTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallSpec,
    CallInvocation,
    CallSpecCompiler,
    RoomAuthority,
    TestSelectiveAgentRuntimeModelProvider
  }

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:fixture, {TestSelectiveAgentRuntimeModelProvider, [owner: self()]})

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "actual room completion waits for admitted diagnostic worker termination" do
    alias Vxpipe.CallEngine.Diagnostics.{RoomService, SourceAdmission}
    alias Vxpipe.CallEngine.Diagnostics.RoomSupervisor, as: DiagnosticSupervisor
    plan = compile_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id
    }

    service = GenServer.whereis(RoomService.address(identity))
    assert is_pid(service)

    assert {:ok, completion} =
             CallEngine.monitor_room_completion(plan.tenant_id, plan.room_id, room.incarnation_id)

    assert {:ok, lease} = SourceAdmission.reserve(SourceAdmission, service)
    parent = self()

    assert {:ok, worker} =
             SourceAdmission.start_worker(
               SourceAdmission,
               lease,
               DiagnosticSupervisor.address(identity, :workers),
               {Task,
                fn ->
                  Process.flag(:trap_exit, true)
                  send(parent, {:worker_ready, self()})

                  receive do
                    {:EXIT, _, :shutdown} ->
                      send(parent, {:worker_stopping, self()})

                      receive do
                        :finish -> :ok
                      end
                  end
                end}
             )

    on_exit(fn -> send(worker, :finish) end)
    assert_receive {:worker_ready, ^worker}
    assert :ok = SourceAdmission.adopt(SourceAdmission, lease)
    monitor = Process.monitor(worker)
    assert :ok = CallEngine.end_call(plan.tenant_id, plan.room_id, room.incarnation_id)
    assert_receive {:worker_stopping, ^worker}, 1_000
    refute_received {:DOWN, ^completion, :process, _, _}
    assert %{occupied_slots: 1} = SourceAdmission.status(SourceAdmission)
    send(worker, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1_000
    assert_receive {:DOWN, ^completion, :process, _, _}, 1_000
    assert %{occupied_slots: 0} = SourceAdmission.status(SourceAdmission)
  end

  test "exhausted optional diagnostics leave actual planned room available" do
    alias Vxpipe.CallEngine.Diagnostics.{RoomService, RoomSupervisor}
    plan = compile_plan()
    assert {:ok, room} = Vxpipe.CallEngine.TestCallStartup.start_call(plan)

    identity = %{
      tenant_id: plan.tenant_id,
      room_id: plan.room_id,
      incarnation_id: room.incarnation_id
    }

    subtree = GenServer.whereis(RoomSupervisor.address(identity, :supervisor))
    subtree_monitor = Process.monitor(subtree)

    for _ <- 1..2 do
      previous = GenServer.whereis(RoomService.address(identity))
      monitor = Process.monitor(previous)
      Process.exit(previous, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^previous, :killed}
      _ = Supervisor.which_children(subtree)
      next = GenServer.whereis(RoomService.address(identity))
      assert is_pid(next)
      refute next == previous
    end

    Process.exit(GenServer.whereis(RoomService.address(identity)), :kill)
    assert_receive {:DOWN, ^subtree_monitor, :process, ^subtree, :shutdown}, 1_000

    assert %{lifecycle: :open, incarnation_id: incarnation} =
             RoomAuthority.snapshot(plan.tenant_id, plan.room_id)

    assert incarnation == room.incarnation_id
  end

  defp compile_plan do
    assert {:ok, spec} =
             CallSpec.new(
               %{
                 schema_version: "20260915.01",
                 entry_caller: "caller",
                 entry_receiver: "agent",
                 defaults: %{capabilities: %{}},
                 participants: %{
                   "caller" => %{
                     type: "human",
                     connection: %{service: "web", mode: "receive", admission: "start_call"}
                   },
                   "agent" => %{
                     type: "agent",
                     prompt: "Answer requests.",
                     first_message: %{mode: "wait_for_input"},
                     capabilities: %{
                       model_inference: %{provider: "fixture", model: "test:scripted"}
                     },
                     tools: %{}
                   }
                 },
                 limits: %{max_duration_ms: 60_000}
               },
               resource_id: "diagnostic-composition",
               revision: 1
             )

    suffix = Integer.to_string(System.unique_integer([:positive, :monotonic]))

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_spec: %{id: "diagnostic-composition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant",
               actor_id: "actor",
               call_id: "call-" <> suffix,
               room_id: "room-" <> suffix
             )

    assert {:ok, plan} = CallSpecCompiler.compile(spec, invocation, %{host_tools: %{}})
    plan
  end
end
