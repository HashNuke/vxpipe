defmodule Vxpipe.Calls.HistoryCursor do
  @moduledoc false

  alias Vxpipe.Calls.{CallFact, VariableSnapshot}

  @enforce_keys [:occurred_at, :source, :position, :record_id]
  defstruct @enforce_keys

  @type source :: :fact | :variable_snapshot
  @type t :: %__MODULE__{
          occurred_at: DateTime.t(),
          source: source(),
          position: non_neg_integer(),
          record_id: String.t()
        }

  @spec from_record(CallFact.t() | VariableSnapshot.t()) :: t()
  def from_record(%CallFact{} = fact) do
    %__MODULE__{
      occurred_at: fact.occurred_at,
      source: :fact,
      position: fact.sequence,
      record_id: fact.id
    }
  end

  def from_record(%VariableSnapshot{} = snapshot) do
    %__MODULE__{
      occurred_at: snapshot.occurred_at,
      source: :variable_snapshot,
      position: snapshot.global_revision,
      record_id: snapshot.id
    }
  end

  @spec record_key(CallFact.t() | VariableSnapshot.t()) :: tuple()
  def record_key(record), do: record |> from_record() |> cursor_key()

  @spec cursor_key(t()) :: tuple()
  def cursor_key(%__MODULE__{} = cursor) do
    {cursor.occurred_at, source_rank(cursor.source), cursor.position, cursor.record_id}
  end

  @spec encode(t()) :: String.t()
  def encode(%__MODULE__{} = cursor) do
    %{
      "occurred_at" => DateTime.to_iso8601(cursor.occurred_at),
      "source" => Atom.to_string(cursor.source),
      "position" => cursor.position,
      "record_id" => cursor.record_id
    }
    |> JSON.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(String.t()) :: {:ok, t()} | {:error, :invalid_cursor}
  def decode(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, decoded} <- JSON.decode(json),
         {:ok, occurred_at, 0} <- DateTime.from_iso8601(decoded["occurred_at"]),
         {:ok, source} <- source(decoded["source"]),
         position when is_integer(position) and position >= 0 <- decoded["position"],
         record_id
         when is_binary(record_id) and byte_size(record_id) > 0 and
                byte_size(record_id) <= 256 <- decoded["record_id"] do
      {:ok,
       %__MODULE__{
         occurred_at: occurred_at,
         source: source,
         position: position,
         record_id: record_id
       }}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  rescue
    _invalid -> {:error, :invalid_cursor}
  end

  def decode(_invalid), do: {:error, :invalid_cursor}

  defp source("fact"), do: {:ok, :fact}
  defp source("variable_snapshot"), do: {:ok, :variable_snapshot}
  defp source(_invalid), do: {:error, :invalid_source}

  defp source_rank(:fact), do: 0
  defp source_rank(:variable_snapshot), do: 1
end
