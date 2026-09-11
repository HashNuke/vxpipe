defmodule Vxpipe.Persistence.PreparedCallRecord do
  @moduledoc false

  alias Vxpipe.Calls.PreparedCall
  alias Vxpipe.Persistence.ResolvedPlanCodec
  alias Vxpipe.Persistence.Schema.Call

  @spec changeset(PreparedCall.t(), struct(), struct()) :: Ecto.Changeset.t()
  def changeset(call, tenant, revision) do
    Call.changeset(%Call{}, %{
      public_id: call.id,
      tenant_id: tenant.id,
      definition_revision_id: revision.id,
      participant_routes: call.participant_routes,
      entry_caller: call.entry_caller,
      entry_receiver: call.entry_receiver,
      initial_variables: call.initial_variables,
      resolved_plan: ResolvedPlanCodec.encode(call.plan),
      plan_digest: call.plan_digest,
      state: call.state,
      room_id: call.room_id,
      created_at: call.created_at,
      started_at: call.started_at,
      ended_at: call.ended_at,
      incarnation_id: call.incarnation_id,
      terminal_reason: call.terminal_reason
    })
  end

  @spec load(Call.t(), {struct(), struct(), struct()}) ::
          {:ok, PreparedCall.t()} | {:error, term()}
  def load(call, {tenant, definition, revision}) do
    with {:ok, plan} <- ResolvedPlanCodec.decode(call.resolved_plan) do
      {:ok,
       %PreparedCall{
         id: call.public_id,
         tenant_key: tenant.key,
         definition_id: definition.public_id,
         definition_revision: revision.revision,
         schema_version: revision.schema_version,
         participant_routes: call.participant_routes,
         entry_caller: call.entry_caller,
         entry_receiver: call.entry_receiver,
         initial_variables: call.initial_variables,
         plan: plan,
         plan_digest: call.plan_digest,
         state: call.state,
         room_id: call.room_id,
         created_at: call.created_at,
         started_at: call.started_at,
         ended_at: call.ended_at,
         incarnation_id: call.incarnation_id,
         terminal_reason: call.terminal_reason
       }}
    end
  end
end
