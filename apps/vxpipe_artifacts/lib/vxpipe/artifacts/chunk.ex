defmodule Vxpipe.Artifacts.Chunk do
  @moduledoc "One bounded PCM interval offered to an artifact writer."

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :sequence,
    :offset_samples,
    :sample_count,
    :channels,
    :timestamp,
    :policy_revision,
    :source_participant_ids,
    :payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sequence: non_neg_integer(),
          offset_samples: non_neg_integer(),
          sample_count: pos_integer(),
          channels: pos_integer(),
          timestamp: non_neg_integer(),
          policy_revision: non_neg_integer(),
          source_participant_ids: [String.t()],
          payload: binary()
        }

  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = chunk) do
    is_integer(chunk.sequence) and chunk.sequence >= 0 and
      is_integer(chunk.offset_samples) and chunk.offset_samples >= 0 and
      is_integer(chunk.sample_count) and chunk.sample_count > 0 and
      is_integer(chunk.channels) and chunk.channels > 0 and chunk.channels <= 8 and
      is_integer(chunk.timestamp) and chunk.timestamp >= 0 and
      is_integer(chunk.policy_revision) and chunk.policy_revision >= 0 and
      valid_sources?(chunk.source_participant_ids) and is_binary(chunk.payload) and
      byte_size(chunk.payload) == chunk.sample_count * chunk.channels * 2
  end

  def valid?(_chunk), do: false

  defp valid_sources?(sources) when is_list(sources) and length(sources) <= 64 do
    Enum.all?(sources, &(is_binary(&1) and &1 != "" and byte_size(&1) <= 128)) and
      length(sources) == length(Enum.uniq(sources))
  end

  defp valid_sources?(_sources), do: false
end
