defmodule Vxpipe.Gateway.CallAdmissionAdapterTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine
  alias Vxpipe.CallEngine.CallDefinition.{ConnectionIntent, VariablePermissions}
  alias Vxpipe.CallEngine.Command.CreateRoom
  alias Vxpipe.CallEngine.ResolvedCallPlan

  alias Vxpipe.CallEngine.ResolvedCallPlan.{
    CallVariables,
    Capabilities,
    Participant,
    ToolVisibility
  }

  alias Vxpipe.Calls.{AdmissionClaim, PreparedCall}
  alias Vxpipe.Gateway.CallAdmission

  test "joins the claimed pinned participant beneath an existing call incarnation" do
    tenant_id = unique_id("tenant")
    room_id = unique_id("room")
    participant_id = unique_id("support")
    plan = resolved_plan(tenant_id, room_id, participant_id)

    assert {:ok, create_room} =
             CreateRoom.new(
               tenant_id: tenant_id,
               actor_id: plan.actor_id,
               room_id: room_id,
               deadline: future_deadline()
             )

    assert {:ok, room} = CallEngine.create_room(create_room)
    started_at = DateTime.add(DateTime.utc_now(), -1, :second)

    claim = %AdmissionClaim{
      call: prepared_call(plan, room.incarnation_id, started_at),
      token_id: unique_id("token"),
      participant_key: unique_id("route"),
      participant_ref: "support",
      participant_id: participant_id,
      accepted_at: DateTime.utc_now()
    }

    assert {:joined, participant} = CallAdmission.start_call([], claim)
    assert participant.tenant_id == tenant_id
    assert participant.room_id == room_id
    assert participant.incarnation_id == room.incarnation_id
    assert participant.participant_id == participant_id
    assert participant.role == :human
  end

  defp prepared_call(plan, incarnation_id, started_at) do
    %PreparedCall{
      id: plan.call_id,
      tenant_key: plan.tenant_id,
      definition_id: plan.definition_id,
      definition_revision: plan.definition_revision,
      schema_version: plan.schema_version,
      participant_routes: %{},
      entry_caller: plan.entry_caller,
      entry_receiver: plan.entry_receiver,
      initial_variables: %{},
      plan: plan,
      plan_digest: :crypto.hash(:sha256, :erlang.term_to_binary(plan)),
      state: :running,
      room_id: plan.room_id,
      created_at: DateTime.add(started_at, -1, :second),
      started_at: started_at,
      ended_at: nil,
      incarnation_id: incarnation_id,
      terminal_reason: nil
    }
  end

  defp resolved_plan(tenant_id, room_id, participant_id) do
    participant = %Participant{
      definition_key: "support",
      participant_id: participant_id,
      activation_id: nil,
      kind: :human,
      description: nil,
      connection: %ConnectionIntent{service: :web, mode: :receive, admission: :start_call},
      prompt: nil,
      first_message: nil,
      first_message_text: nil,
      capabilities: %Capabilities{},
      tools: %{},
      transfers: [],
      variable_permissions: %VariablePermissions{}
    }

    %ResolvedCallPlan{
      definition_id: unique_id("definition"),
      definition_revision: 1,
      schema_version: "20260910.02",
      tenant_id: tenant_id,
      actor_id: unique_id("actor"),
      call_id: unique_id("call"),
      room_id: room_id,
      transport: :web,
      entry_caller: "caller",
      entry_receiver: "assistant",
      opening_audio: nil,
      participants: %{"support" => participant},
      call_variables: %CallVariables{},
      tool_visibility: ToolVisibility.hidden(),
      max_duration_ms: 60_000
    }
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)

  defp unique_id(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
