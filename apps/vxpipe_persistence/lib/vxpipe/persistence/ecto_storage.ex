defmodule Vxpipe.Persistence.EctoStorage do
  @moduledoc "Projects private engine archive facts through Calls-owned workflows."

  @behaviour Vxpipe.CallEngine.Archive.Writer

  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.Calls
  alias Vxpipe.Calls.VariableSnapshot

  @terminal_errors [
    :call_incarnation_mismatch,
    :call_not_found,
    :call_not_started,
    :invalid_variable_snapshot,
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

  def write(_options, _unsupported), do: {:discard, :unsupported_archive_fact}

  defp baseline_snapshot(fact) do
    VariableSnapshot.new(
      common_attributes(fact) ++
        [kind: :baseline]
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
end
