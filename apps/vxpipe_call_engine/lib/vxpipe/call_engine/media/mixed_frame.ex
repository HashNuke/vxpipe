defmodule Vxpipe.CallEngine.Media.MixedFrame do
  @moduledoc """
  One authorized PCM output frame produced by the room mixer.
  """

  @derive {Inspect, except: [:payload]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :subscription_id,
    :recipient_participant_id,
    :mode,
    :source_participant_ids,
    :timestamp,
    :policy_revision,
    :sample_rate,
    :channels,
    :payload
  ]
  defstruct @enforce_keys

  @type mode :: :mix_minus | :full_mix | {:individual_track, String.t()}

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          subscription_id: String.t(),
          recipient_participant_id: String.t(),
          mode: mode(),
          source_participant_ids: [String.t()],
          timestamp: non_neg_integer(),
          policy_revision: non_neg_integer(),
          sample_rate: pos_integer(),
          channels: pos_integer(),
          payload: binary()
        }
end
