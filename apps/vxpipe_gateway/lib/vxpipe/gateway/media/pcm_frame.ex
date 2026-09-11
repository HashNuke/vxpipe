defmodule Vxpipe.Gateway.Media.PCMFrame do
  @moduledoc """
  A decoded audio frame aligned to the room mixer's PCM contract.
  """

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_id,
    :track_id,
    :timestamp,
    :sample_rate,
    :channels,
    :payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          participant_id: String.t(),
          connection_id: String.t(),
          track_id: String.t(),
          timestamp: non_neg_integer(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          payload: binary()
        }
end
