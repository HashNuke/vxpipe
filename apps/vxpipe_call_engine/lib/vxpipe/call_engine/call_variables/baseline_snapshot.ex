defmodule Vxpipe.CallEngine.CallVariables.BaselineSnapshot do
  @moduledoc "Private archival handoff for initial Call Variables."

  @derive {Inspect, except: [:sections]}
  @enforce_keys [
    :id,
    :tenant_id,
    :call_id,
    :room_id,
    :incarnation_id,
    :global_revision,
    :sections,
    :source_policy,
    :occurred_at
  ]
  defstruct @enforce_keys

  @type section_snapshot :: %{revision: non_neg_integer(), value: nil | map()}
  @type t :: %__MODULE__{
          id: String.t(),
          tenant_id: String.t(),
          call_id: String.t(),
          room_id: String.t(),
          incarnation_id: String.t(),
          global_revision: 0,
          sections: %{String.t() => section_snapshot()},
          source_policy: map(),
          occurred_at: DateTime.t()
        }
end
