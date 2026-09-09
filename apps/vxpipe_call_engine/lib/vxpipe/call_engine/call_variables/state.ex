defmodule Vxpipe.CallEngine.CallVariables.State do
  @moduledoc false

  @derive {Inspect, except: [:sections, :grants]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :sections,
    :grants,
    :global_revision
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          sections: map(),
          grants: map(),
          global_revision: non_neg_integer()
        }
end
