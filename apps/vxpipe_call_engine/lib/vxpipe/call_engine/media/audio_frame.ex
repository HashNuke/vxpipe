defmodule Vxpipe.CallEngine.Media.AudioFrame do
  @moduledoc """
  Protocol-neutral audio received for one attached connection and media track.
  """

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :track_id,
    :codec,
    :sample_rate,
    :channels,
    :sequence_number,
    :timestamp,
    :payload,
    :received_at
  ]
  defstruct @enforce_keys ++ [source_epoch: nil, activity_pcm: nil]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          connection_id: String.t(),
          track_id: String.t(),
          codec: :linear16 | :opus,
          sample_rate: pos_integer(),
          channels: pos_integer(),
          sequence_number: non_neg_integer(),
          timestamp: non_neg_integer(),
          payload: binary(),
          received_at: integer(),
          source_epoch: nil | reference(),
          activity_pcm:
            nil
            | %{
                payload: binary(),
                sample_rate: pos_integer(),
                channels: 1,
                timestamp: non_neg_integer()
              }
        }
  @doc "Retained payload bytes, including decoded PCM carried for optional activity detection."
  def bytes(%__MODULE__{payload: payload, activity_pcm: nil}) when is_binary(payload),
    do: byte_size(payload)

  def bytes(%__MODULE__{payload: payload, activity_pcm: %{payload: pcm} = decoded})
      when is_binary(payload) and is_binary(pcm) and map_size(decoded) == 4,
      do: byte_size(payload) + byte_size(pcm)

  def bytes(_frame), do: 131_073
end
