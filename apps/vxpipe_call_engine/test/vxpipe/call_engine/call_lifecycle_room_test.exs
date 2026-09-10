defmodule Vxpipe.CallEngine.CallLifecycleRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestAgentRuntimeModelProvider,
    TestCallLifecycleTimer
  }

  alias Vxpipe.CallEngine.Command.AttachConnection

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

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

  test "fails an unready call when its startup deadline expires" do
    plan = compile_plan(60_000)
    assert {:ok, room} = start_call(plan)
    authority = room_authority(plan)
    monitor = Process.monitor(authority)

    assert_receive {:test_call_lifecycle_timer_scheduled, {_lifecycle, _token, :max_duration},
                    60_000}

    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}
    assert {_lifecycle, _token, :readiness} = readiness_timer

    :ok = TestCallLifecycleTimer.fire(readiness_timer)

    assert_receive {:DOWN, ^monitor, :process, ^authority,
                    {:shutdown, :startup_readiness_timeout}}

    refute room.incarnation_id == ""
  end

  test "ends a ready call at its pinned maximum duration" do
    plan = compile_plan(1_000)
    assert {:ok, room} = start_call(plan)

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 1_000}
    assert {_lifecycle, _token, :max_duration} = maximum_timer
    assert_receive {:test_call_lifecycle_timer_scheduled, readiness_timer, 30_000}

    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, attachment} = attach(plan, room, caller)
    assert_receive {:test_call_lifecycle_timer_cancelled, ^readiness_timer}

    :ok = TestCallLifecycleTimer.fire(maximum_timer)

    assert_receive {:DOWN, monitor, :process, _authority, {:shutdown, :maximum_duration_reached}}
    assert monitor == attachment.room_monitor
  end

  defp start_call(plan) do
    CallEngine.start_call(plan,
      call_lifecycle: [
        readiness_timeout_ms: 30_000,
        timer: {TestCallLifecycleTimer, [observer: self()]}
      ]
    )
  end

  defp compile_plan(max_duration_ms) do
    input = %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Wait for the caller.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: max_duration_ms}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "lifecycle-definition", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "lifecycle-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-lifecycle",
               actor_id: "actor-lifecycle",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp attach(plan, room, caller) do
    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: unique_id("connection"),
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    CallEngine.attach_connection(command)
  end

  defp room_authority(plan) do
    [{authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    authority
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
end
