defmodule Vxpipe.CallEngine.Recording.Chunk do
  @moduledoc "One bounded, clock-aligned PCM interval offered by a room recording."

  alias Vxpipe.CallEngine.Media.MixedFrame

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :sequence,
    :offset_samples,
    :sample_count,
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
          timestamp: non_neg_integer(),
          policy_revision: non_neg_integer(),
          source_participant_ids: [String.t()],
          payload: binary()
        }

  @spec from_mixed_frame(MixedFrame.t(), non_neg_integer()) ::
          {:ok, t()} | {:error, :invalid_recording_frame}
  def from_mixed_frame(%MixedFrame{} = frame, sequence)
      when is_integer(sequence) and sequence >= 0 do
    bytes_per_sample_frame = frame.channels * 2

    if bytes_per_sample_frame > 0 and byte_size(frame.payload) > 0 and
         rem(byte_size(frame.payload), bytes_per_sample_frame) == 0 do
      {:ok,
       %__MODULE__{
         sequence: sequence,
         offset_samples: frame.timestamp,
         sample_count: div(byte_size(frame.payload), bytes_per_sample_frame),
         timestamp: frame.timestamp,
         policy_revision: frame.policy_revision,
         source_participant_ids: frame.source_participant_ids,
         payload: frame.payload
       }}
    else
      {:error, :invalid_recording_frame}
    end
  end

  def from_mixed_frame(_frame, _sequence), do: {:error, :invalid_recording_frame}
end
