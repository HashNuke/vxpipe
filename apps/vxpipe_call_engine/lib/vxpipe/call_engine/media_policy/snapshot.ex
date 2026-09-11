defmodule Vxpipe.CallEngine.MediaPolicy.Snapshot do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Effective

  @enforce_keys [:revision, :present_participant_ids, :effective]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          revision: non_neg_integer(),
          present_participant_ids: MapSet.t(String.t()),
          effective: Effective.t()
        }
end
