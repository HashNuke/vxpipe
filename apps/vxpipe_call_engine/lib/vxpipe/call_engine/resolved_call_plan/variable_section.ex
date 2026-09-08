defmodule Vxpipe.CallEngine.ResolvedCallPlan.VariableSection do
  @moduledoc false

  @derive {Inspect, except: [:validator]}
  @enforce_keys [:name, :schema, :validator, :value, :revision]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          schema: map(),
          validator: JSV.Root.t(),
          value: nil | map(),
          revision: non_neg_integer()
        }
end
