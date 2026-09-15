defmodule Vxpipe.CallEngine.LiveInspectionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Command.UpdateCallVariables
  alias Vxpipe.CallEngine.LiveInspection.{Buffer, Port}

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    CallVariables,
    DefinitionCompiler
  }

  @identity %{
    tenant_id: "tenant-inspection",
    call_id: "call-inspection",
    room_id: "room-inspection",
    incarnation_id: "rinc-inspection"
  }

  test "readiness requires an open local observation handoff and never exposes retained data" do
    buffer =
      start_supervised!(
        {Buffer, identity: @identity, maximum_pending_records: 8, maximum_retained_records: 3}
      )

    assert {:ok, resource, :ready} = Buffer.readiness(buffer)
    assert resource.kind == :live_inspection
    assert {:ok, port} = Buffer.port(buffer)
    assert :ok = Port.offer(port, variable_update())
    assert {:ok, ^resource, :ready} = Buffer.readiness(buffer)
    refute inspect(resource) =~ "private-live-value"

    :ok = Port.close(port)
    assert {:ok, ^resource, :failed} = Buffer.readiness(buffer)
  end

  test "retains a bounded private live projection without blocking its producers" do
    buffer =
      start_supervised!(
        {Buffer, identity: @identity, maximum_pending_records: 8, maximum_retained_records: 3}
      )

    assert {:ok, port} = Buffer.port(buffer)

    assert :ok = Port.offer(port, fact(1, :room_opened))
    assert :ok = Port.offer(port, fact(2, :tool_call_started))
    assert :ok = Port.offer(port, variable_update())
    assert :ok = Port.offer(port, fact(3, :tool_call_completed))

    assert {:ok, snapshot} =
             CallEngine.inspect_live_call(@identity.tenant_id, @identity.call_id)

    assert snapshot.incarnation_id == @identity.incarnation_id
    assert snapshot.latest_fact_sequence == 3
    assert snapshot.latest_variable_revision == 1
    assert snapshot.dropped_records == 1
    assert snapshot.rejected_records == 0
    assert Enum.map(snapshot.records, & &1.id) == ["fact-2", "snapshot-1", "fact-3"]
    refute inspect(snapshot) =~ "private-live-value"
    assert Port.stats(port).pending == 0

    stop_supervised!({Buffer, @identity.incarnation_id})

    assert {:error, :call_not_live} =
             CallEngine.inspect_live_call(@identity.tenant_id, @identity.call_id)
  end

  test "projects planned-room facts and accepted Call Variables without archival storage" do
    plan = resolved_plan()
    receiver = Map.fetch!(plan.participants, plan.entry_receiver)

    assert {:ok, room} = CallEngine.start_call(plan)

    assert {:ok, initial} = await_snapshot(plan, &(&1.latest_variable_revision == 0))
    assert initial.incarnation_id == room.incarnation_id
    assert Enum.any?(initial.records, &match?(%Fact{kind: :room_opened}, &1))
    assert Enum.any?(initial.records, &match?(%BaselineSnapshot{global_revision: 0}, &1))

    variables = CallVariables.whereis(room.incarnation_id)

    assert {:ok, command} =
             UpdateCallVariables.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: receiver.participant_id,
               activation_id: receiver.activation_id,
               source_participant_id:
                 plan.participants |> Map.fetch!(plan.entry_caller) |> Map.fetch!(:participant_id),
               correlation_id: unique_id("turn"),
               tool_call_id: unique_id("tool"),
               section: "intake",
               expected_revision: 0,
               operation: {:merge, %{"summary" => "private-live-value"}},
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    assert {:ok, %{"global_revision" => 1}} = CallVariables.update(variables, command)
    assert {:ok, updated} = await_snapshot(plan, &(&1.latest_variable_revision == 1))

    assert Enum.any?(updated.records, fn
             %UpdateSnapshot{
               command_id: command_id,
               participant_id: participant_id,
               global_revision: 1
             } ->
               command_id == command.id and participant_id == receiver.participant_id

             _record ->
               false
           end)

    refute inspect(updated) =~ "private-live-value"

    assert {:ok, inspection_port} = Buffer.port(plan.tenant_id, plan.call_id)
    incarnation_supervisor = incarnation_supervisor_for(inspection_port.buffer)
    inspection_monitor = Process.monitor(inspection_port.buffer)
    Process.exit(inspection_port.buffer, :kill)

    assert_receive {:DOWN, ^inspection_monitor, :process, _buffer, :killed}
    _ = :sys.get_state(incarnation_supervisor)

    assert {:error, :call_not_live} =
             CallEngine.inspect_live_call(plan.tenant_id, plan.call_id)

    assert {:ok, participant} =
             CallEngine.participant_snapshot(
               plan.tenant_id,
               plan.room_id,
               receiver.participant_id
             )

    assert participant.participant_id == receiver.participant_id
  end

  defp fact(sequence, kind) do
    payload =
      case kind do
        :room_opened -> %{"lifecycle" => "open"}
        :tool_call_started -> %{"arguments" => %{}, "name" => "slow_lookup"}
        :tool_call_completed -> %{"name" => "slow_lookup", "result" => %{"ok" => true}}
      end

    Fact.new!(
      id: "fact-#{sequence}",
      kind: kind,
      sequence: sequence,
      tenant_id: @identity.tenant_id,
      call_id: @identity.call_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      participant_id: "assistant-1",
      activation_id: "activation-1",
      correlation_id: "turn-1",
      tool_call_id: if(kind == :room_opened, do: nil, else: "tool-1"),
      occurred_at: DateTime.add(~U[2026-09-09 15:00:00.000000Z], sequence, :second),
      source_policy: %{"revision" => 0},
      payload: payload
    )
  end

  defp variable_update do
    %UpdateSnapshot{
      id: "snapshot-1",
      command_id: "command-1",
      tenant_id: @identity.tenant_id,
      call_id: @identity.call_id,
      room_id: @identity.room_id,
      incarnation_id: @identity.incarnation_id,
      participant_id: "assistant-1",
      activation_id: "activation-1",
      source_participant_id: "caller-1",
      correlation_id: "turn-1",
      tool_call_id: "tool-1",
      section: "order",
      section_revision: 1,
      global_revision: 1,
      sections: %{
        "order" => %{revision: 1, value: %{"status" => "private-live-value"}}
      },
      source_policy: %{"revision" => 0},
      occurred_at: ~U[2026-09-09 15:00:02.000000Z]
    }
  end

  defp resolved_plan do
    suffix = System.unique_integer([:positive, :monotonic])
    resource_id = "inspection-definition-#{suffix}"

    definition_input = %{
      schema_version: "20260915.01",
      entry_caller: "caller",
      entry_receiver: "assistant",
      defaults: %{
        capabilities: %{model_inference: %{provider: "fixture", model: "test:scripted"}}
      },
      call_variables: %{
        sections: %{
          "order" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"id" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          },
          "intake" => %{
            schema: %{
              "type" => "object",
              "properties" => %{"summary" => %{"type" => "string"}},
              "additionalProperties" => false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{
          type: "agent",
          prompt: "Answer briefly.",
          first_message: %{mode: "wait_for_input"},
          variable_permissions: %{
            "order" => ["read"],
            "intake" => ["read", "write"]
          }
        }
      }
    }

    assert {:ok, definition} =
             CallDefinition.new(definition_input, resource_id: resource_id, revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: resource_id, revision: 1},
                 initial_variables: %{"order" => %{"id" => "order-1"}},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-inspection-room",
               actor_id: "actor-inspection-room",
               call_id: "call-inspection-room-#{suffix}",
               room_id: "room-inspection-room-#{suffix}"
             )

    registries = %{
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp await_snapshot(plan, predicate, attempts \\ 100)

  defp await_snapshot(plan, predicate, attempts) when attempts > 0 do
    case CallEngine.inspect_live_call(plan.tenant_id, plan.call_id) do
      {:ok, snapshot} = result ->
        if predicate.(snapshot), do: result, else: await_snapshot(plan, predicate, attempts - 1)

      {:error, :call_not_live} ->
        await_snapshot(plan, predicate, attempts - 1)
    end
  end

  defp await_snapshot(_plan, _predicate, 0), do: {:error, :projection_timeout}

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp incarnation_supervisor_for(buffer) do
    Vxpipe.CallEngine.RoomSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.find_value(fn {_id, supervisor, :supervisor, _modules} ->
      if Enum.any?(Supervisor.which_children(supervisor), fn
           {_id, ^buffer, :worker, _modules} -> true
           _child -> false
         end) do
        supervisor
      end
    end)
  end
end
