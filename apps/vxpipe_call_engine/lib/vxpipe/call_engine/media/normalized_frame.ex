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
  defstruct @enforce_keys ++
              [
                origin: :participant,
                recording_duplicate_frames: 0,
                recording_selected_connection_id: nil,
                recording_equivalent_max_order: nil
              ]

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
          origin: :participant | :room,
          recording_duplicate_frames: non_neg_integer(),
          recording_selected_connection_id: nil | String.t(),
          recording_equivalent_max_order: nil | non_neg_integer(),
          payload: binary()
        }
end
