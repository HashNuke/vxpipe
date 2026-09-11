defmodule Vxpipe.CallEngine.Media.NormalizedFrame do
  @moduledoc """
  One policy-tagged signed 16-bit little-endian PCM frame on the room media clock.
  """

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :source_participant_id,
    :connection_id,
    :track_id,
    :sequence_number,
    :timestamp,
    :policy_revision,
    :sample_rate,
    :channels,
    :payload
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_participant_id: String.t(),
          connection_id: String.t(),
          track_id: String.t(),
          sequence_number: non_neg_integer(),
          timestamp: non_neg_integer(),
          policy_revision: non_neg_integer(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          payload: binary()
        }
end
