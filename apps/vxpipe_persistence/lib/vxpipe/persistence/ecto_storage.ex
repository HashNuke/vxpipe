defmodule Vxpipe.Persistence.EctoStorage do
  @moduledoc "Projects private engine archive facts through Calls-owned workflows."

  @behaviour Vxpipe.CallEngine.Archive.Writer

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Archive.Fact, as: EngineFact
  alias Vxpipe.Calls
  alias Vxpipe.Calls.CallFact
  alias Vxpipe.Calls.VariableSnapshot

  @terminal_errors [
    :call_incarnation_mismatch,
    :call_fact_conflict,
    :call_fact_insert_failed,
    :call_fact_sequence_conflict,
    :call_not_found,
    :call_not_started,
    :invalid_variable_snapshot,
    :invalid_call_fact,
    :variable_snapshot_conflict,
    :variable_snapshot_revision_conflict
  ]

  @impl true
  def write(options, %BaselineSnapshot{} = fact) when is_list(options) do
    fact
    |> baseline_snapshot()
    |> store(options)
  end

  def write(options, %UpdateSnapshot{} = fact) when is_list(options) do
    fact
    |> update_snapshot()
    |> store(options)
  end

  def write(options, %EngineFact{} = fact) when is_list(options) do
    fact
    |> call_fact()
    |> store_call_fact(options)
  end

  def write(_options, _unsupported), do: {:discard, :unsupported_archive_fact}

  defp baseline_snapshot(fact) do
    VariableSnapshot.new(
      common_attributes(fact) ++
        [kind: :baseline]
    )
  end

  defp call_fact(fact) do
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

  defp update_snapshot(fact) do
    VariableSnapshot.new(
      common_attributes(fact) ++
        [
          kind: :update,
          command_id: fact.command_id,
          participant_id: fact.participant_id,
          activation_id: fact.activation_id,
          source_participant_id: fact.source_participant_id,
          correlation_id: fact.correlation_id,
          tool_call_id: fact.tool_call_id,
          section: fact.section,
          section_revision: fact.section_revision
        ]
    )
  end

  defp common_attributes(fact) do
    [
      id: fact.id,
      tenant_key: fact.tenant_id,
      call_id: fact.call_id,
      room_id: fact.room_id,
      incarnation_id: fact.incarnation_id,
      global_revision: fact.global_revision,
      sections: fact.sections,
      source_policy: fact.source_policy,
      occurred_at: fact.occurred_at
    ]
  end

  defp store({:ok, snapshot}, options) do
    case Calls.archive_variable_snapshot(snapshot, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store({:error, reason}, _options), do: {:discard, reason}

  defp store_call_fact({:ok, fact}, options) do
    case Calls.archive_call_fact(fact, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store_call_fact({:error, reason}, _options), do: {:discard, reason}
end
