defmodule Vxpipe.CallEngine.TranscriptRouter.Decision do
  @moduledoc false

  @enforce_keys [:recipient_participant_ids, :source_policy]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          recipient_participant_ids: MapSet.t(String.t()),
          source_policy: %{
            required(String.t()) => JSON.value()
          }
        }
end
