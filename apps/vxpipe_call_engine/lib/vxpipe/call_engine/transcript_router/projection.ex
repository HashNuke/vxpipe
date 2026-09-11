defmodule Vxpipe.CallEngine.TranscriptRouter.Projection do
  @moduledoc false

  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :source_participant_id,
    :policy_revision,
    :recipient_participant_ids
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          source_participant_id: String.t(),
          policy_revision: non_neg_integer(),
          recipient_participant_ids: MapSet.t(String.t())
        }
end
