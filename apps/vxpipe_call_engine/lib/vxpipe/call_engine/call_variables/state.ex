defmodule Vxpipe.CallEngine.CallVariables.State do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.ArchivalPort

  @derive {Inspect, except: [:sections, :grants, :archival_port]}
  @enforce_keys [
    :tenant_id,
    :room_id,
    :incarnation_id,
    :sections,
    :grants,
    :archival_port,
    :global_revision
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          sections: map(),
          grants: map(),
          archival_port: ArchivalPort.t(),
          global_revision: non_neg_integer()
        }
end
