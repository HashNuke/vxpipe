defmodule Vxpipe.Calls.LiveCallInspection do
  @moduledoc "An authorized Calls-owned view of one engine live projection."

  alias Vxpipe.CallEngine.LiveInspection.Snapshot, as: EngineSnapshot

  alias Vxpipe.Calls.{
    CallFact,
    CallTimeline,
    CallTimelineEntry,
    EngineArchiveProjection,
    VariableSnapshot
  }

  @derive {Inspect, except: [:timeline]}
  @enforce_keys [
    :tenant_key,
    :call_id,
    :room_id,
    :incarnation_id,
    :timeline,
    :latest_fact_sequence,
    :live_variable_revision,
    :dropped_records,
    :rejected_records
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_key: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          timeline: [CallTimelineEntry.t()],
          latest_fact_sequence: pos_integer() | nil,
          live_variable_revision: non_neg_integer() | nil,
          dropped_records: non_neg_integer(),
          rejected_records: non_neg_integer()
        }

  @spec from_engine(EngineSnapshot.t(), String.t(), String.t()) ::
          {:ok, t()} | {:error, :invalid_live_inspection}
  def from_engine(%EngineSnapshot{} = snapshot, tenant_key, call_id) do
    with :ok <- validate_snapshot(snapshot, tenant_key, call_id),
         {:ok, records} <- project_records(snapshot.records),
         :ok <- validate_records(records, snapshot) do
      {facts, variable_snapshots} = Enum.split_with(records, &match?(%CallFact{}, &1))

      {:ok,
       %__MODULE__{
         tenant_key: tenant_key,
         call_id: call_id,
         room_id: snapshot.room_id,
         incarnation_id: snapshot.incarnation_id,
         timeline:
           CallTimeline.project(facts, variable_snapshots, source: :live, order: :desc),
         latest_fact_sequence: snapshot.latest_fact_sequence,
         live_variable_revision: snapshot.latest_variable_revision,
         dropped_records: snapshot.dropped_records,
         rejected_records: snapshot.rejected_records
       }}
    else
      _invalid -> {:error, :invalid_live_inspection}
    end
  end

  def from_engine(_snapshot, _tenant_key, _call_id), do: {:error, :invalid_live_inspection}

  defp validate_snapshot(snapshot, tenant_key, call_id) do
    valid_identifiers? =
      snapshot.tenant_id == tenant_key and snapshot.call_id == call_id and
        valid_identifier?(snapshot.room_id) and valid_identifier?(snapshot.incarnation_id)

    valid_counters? =
      valid_optional_positive?(snapshot.latest_fact_sequence) and
        valid_optional_non_negative?(snapshot.latest_variable_revision) and
        valid_non_negative?(snapshot.dropped_records) and
        valid_non_negative?(snapshot.rejected_records)

    if valid_identifiers? and valid_counters? and is_list(snapshot.records),
      do: :ok,
      else: {:error, :invalid_snapshot}
  end

  defp project_records(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, projected} ->
      case EngineArchiveProjection.project(record) do
        {:ok, value} -> {:cont, {:ok, [value | projected]}}
        {:error, _reason} -> {:halt, {:error, :invalid_record}}
      end
    end)
    |> case do
      {:ok, projected} -> {:ok, Enum.reverse(projected)}
      {:error, :invalid_record} = error -> error
    end
  end

  defp validate_records(records, snapshot) do
    if Enum.all?(records, &belongs_to_snapshot?(&1, snapshot)),
      do: :ok,
      else: {:error, :record_identity_mismatch}
  end

  defp belongs_to_snapshot?(%CallFact{} = record, snapshot), do: matching?(record, snapshot)

  defp belongs_to_snapshot?(%VariableSnapshot{} = record, snapshot),
    do: matching?(record, snapshot)

  defp matching?(record, snapshot) do
    record.tenant_key == snapshot.tenant_id and record.call_id == snapshot.call_id and
      record.room_id == snapshot.room_id and record.incarnation_id == snapshot.incarnation_id
  end

  defp valid_identifier?(value),
    do: is_binary(value) and byte_size(value) > 0 and byte_size(value) <= 256

  defp valid_optional_positive?(nil), do: true
  defp valid_optional_positive?(value), do: is_integer(value) and value > 0

  defp valid_optional_non_negative?(nil), do: true
  defp valid_optional_non_negative?(value), do: valid_non_negative?(value)

  defp valid_non_negative?(value), do: is_integer(value) and value >= 0
end
