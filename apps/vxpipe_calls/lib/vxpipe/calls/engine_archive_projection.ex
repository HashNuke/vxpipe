defmodule Vxpipe.Calls.EngineArchiveProjection do
  @moduledoc "Translates engine-private archive records into Calls-owned values."

  alias Vxpipe.CallEngine.Archive.Fact, as: EngineFact
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.Calls.{CallFact, VariableSnapshot}

  @type engine_record :: EngineFact.t() | BaselineSnapshot.t() | UpdateSnapshot.t()

  @spec project(engine_record()) ::
          {:ok, CallFact.t() | VariableSnapshot.t()}
          | {:error,
             :invalid_call_fact | :invalid_variable_snapshot | :unsupported_engine_record}
  def project(%EngineFact{} = fact) do
    CallFact.new(
      id: fact.id,
      kind: fact.kind,
      sequence: fact.sequence,
      tenant_key: fact.tenant_id,
      call_id: fact.call_id,
      room_id: fact.room_id,
      incarnation_id: fact.incarnation_id,
      participant_id: fact.participant_id,
      activation_id: fact.activation_id,
      source_participant_id: fact.source_participant_id,
      connection_id: fact.connection_id,
      command_id: fact.command_id,
      correlation_id: fact.correlation_id,
      tool_call_id: fact.tool_call_id,
      public_sequence: fact.public_sequence,
      occurred_at: fact.occurred_at,
      source_policy: fact.source_policy,
      payload: fact.payload
    )
  end

  def project(%BaselineSnapshot{} = snapshot) do
    snapshot
    |> common_attributes()
    |> Keyword.put(:kind, :baseline)
    |> VariableSnapshot.new()
  end

  def project(%UpdateSnapshot{} = snapshot) do
    snapshot
    |> common_attributes()
    |> Keyword.merge(
      kind: :update,
      command_id: snapshot.command_id,
      participant_id: snapshot.participant_id,
      activation_id: snapshot.activation_id,
      source_participant_id: snapshot.source_participant_id,
      correlation_id: snapshot.correlation_id,
      tool_call_id: snapshot.tool_call_id,
      section: snapshot.section,
      section_revision: snapshot.section_revision
    )
    |> VariableSnapshot.new()
  end

  def project(_unsupported), do: {:error, :unsupported_engine_record}

  defp common_attributes(snapshot) do
    [
      id: snapshot.id,
      tenant_key: snapshot.tenant_id,
      call_id: snapshot.call_id,
      room_id: snapshot.room_id,
      incarnation_id: snapshot.incarnation_id,
      global_revision: snapshot.global_revision,
      sections: snapshot.sections,
      source_policy: snapshot.source_policy,
      occurred_at: snapshot.occurred_at
    ]
  end
end
