defmodule Vxpipe.CallEngine.TelephonyCallStartupTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestCallLifecycleTimer
  }

  test "starts a pinned telephony receive call through the ordinary room lifecycle" do
    plan = compile_plan()
    caller = Map.fetch!(plan.participants, plan.entry_caller)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               call_lifecycle: [
                 readiness_timeout_ms: 30_000,
                 idle_timeout_ms: 15_000,
                 timer: {TestCallLifecycleTimer, [observer: self()]}
               ]
             )

    assert_receive {:test_call_lifecycle_timer_scheduled, maximum_timer, 1_000}
    assert_receive {:test_call_lifecycle_timer_scheduled, _readiness_timer, 30_000}

    assert {:ok, participant} =
             CallEngine.participant_snapshot(plan.tenant_id, plan.room_id, caller.participant_id)

    assert participant.state == :joined
    assert participant.role == :human

    [{authority, _value}] =
      Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id})

    monitor = Process.monitor(authority)
    :ok = TestCallLifecycleTimer.fire(maximum_timer)

    assert_receive {:DOWN, ^monitor, :process, ^authority, {:shutdown, :maximum_duration_reached}}

    refute room.incarnation_id == ""
  end

  defp compile_plan do
    definition_input = %{
      schema_version: "20260913.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{capabilities: %{model_inference: "test-model"}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{
            service: "primary-phone",
            mode: "receive",
            admission: "start_call",
            number: "+15550001000"
          }
        },
        "assistant" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 1_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(definition_input,
               resource_id: "inbound-phone",
               revision: 1
             )

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "inbound-phone", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "telephony"}
               },
               tenant_id: "tenant-phone",
               actor_id: "actor-phone",
               call_id: "call-phone",
               room_id: "room-phone-#{System.unique_integer([:positive])}"
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "google:test-model"}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end
end
