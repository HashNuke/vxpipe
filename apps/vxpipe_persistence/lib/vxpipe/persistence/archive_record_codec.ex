defmodule Vxpipe.Persistence.ArchiveRecordCodec do
  @moduledoc false

  alias Vxpipe.Calls.{CallFact, VariableSnapshot}

  @spec call_fact(struct(), String.t(), String.t()) ::
          {:ok, CallFact.t()} | {:error, :invalid_call_fact}
  def call_fact(stored, tenant_key, call_id) do
    with {:ok, kind} <- CallFact.decode_kind(stored.kind) do
      CallFact.new(
        id: stored.public_id,
        kind: kind,
        sequence: stored.sequence,
        tenant_key: tenant_key,
        call_id: call_id,
        room_id: stored.room_id,
        incarnation_id: stored.incarnation_id,
        participant_id: stored.participant_id,
        activation_id: stored.activation_id,
        source_participant_id: stored.source_participant_id,
        connection_id: stored.connection_id,
        command_id: stored.command_id,
        correlation_id: stored.correlation_id,
        tool_call_id: stored.tool_call_id,
        public_sequence: stored.public_sequence,
        occurred_at: stored.occurred_at,
        source_policy: stored.source_policy,
        payload: stored.payload
      )
    else
      :error -> {:error, :invalid_call_fact}
    end
  rescue
    ArgumentError -> {:error, :invalid_call_fact}
  end

  @spec call_facts([struct()], String.t(), String.t()) ::
          {:ok, [CallFact.t()]} | {:error, :invalid_call_fact}
  def call_facts(stored_facts, tenant_key, call_id) do
    convert(stored_facts, &call_fact(&1, tenant_key, call_id))
  end

  @spec variable_snapshot(struct(), String.t(), String.t()) ::
          {:ok, VariableSnapshot.t()} | {:error, :invalid_variable_snapshot}
  def variable_snapshot(stored, tenant_key, call_id) do
    VariableSnapshot.new(
      id: stored.public_id,
      kind: stored.kind,
      tenant_key: tenant_key,
      call_id: call_id,
      room_id: stored.room_id,
      incarnation_id: stored.incarnation_id,
      global_revision: stored.global_revision,
      sections: decode_sections(stored.sections),
      source_policy: stored.source_policy,
      occurred_at: stored.occurred_at,
      command_id: stored.command_id,
      participant_id: stored.participant_id,
      activation_id: stored.activation_id,
      source_participant_id: stored.source_participant_id,
      correlation_id: stored.correlation_id,
      tool_call_id: stored.tool_call_id,
      section: stored.section,
      section_revision: stored.section_revision
    )
  end

  @spec variable_snapshots([struct()], String.t(), String.t()) ::
          {:ok, [VariableSnapshot.t()]} | {:error, :invalid_variable_snapshot}
  def variable_snapshots(stored_snapshots, tenant_key, call_id) do
    convert(stored_snapshots, &variable_snapshot(&1, tenant_key, call_id))
  end

  defp decode_sections(sections) do
    Map.new(sections, fn {name, section} ->
      {name,
       %{
         revision: Map.fetch!(section, "revision"),
         value: Map.get(section, "value")
       }}
    end)
  end

  defp convert(records, converter) do
    Enum.reduce_while(records, {:ok, []}, fn stored, {:ok, converted} ->
      case converter.(stored) do
        {:ok, record} -> {:cont, {:ok, [record | converted]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, converted} -> {:ok, Enum.reverse(converted)}
      {:error, _reason} = error -> error
    end
  end
end
