defmodule Vxpipe.CallEngine.CallVariables.State do
  @moduledoc false

  alias Vxpipe.CallEngine.CallVariables.{ArchivalPort, InspectionPort}

  @derive {Inspect, except: [:sections, :grants, :archival_port, :inspection_port]}
  @enforce_keys [
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :sections,
    :grants,
    :archival_port,
    :inspection_port,
    :source_policy,
    :global_revision
  ]
  defstruct @enforce_keys ++ [readiness_resource: nil]

  @type t :: %__MODULE__{
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          sections: map(),
          grants: map(),
          archival_port: ArchivalPort.t(),
          inspection_port: InspectionPort.t(),
          source_policy: map(),
          global_revision: non_neg_integer(),
          readiness_resource: Vxpipe.CallEngine.Readiness.Resource.t()
        }
end
