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
  defstruct @enforce_keys

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
          received_at: integer()
        }
end
