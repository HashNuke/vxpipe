defmodule Vxpipe.Persistence.CallDetailsSourceRead do
  @moduledoc false

  @fields [
    :call,
    :facts,
    :variable_snapshots,
    :artifacts,
    :usage_observations,
    :usage_amounts,
    :telephony_legs
  ]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          call: Vxpipe.Calls.PreparedCall.t(),
          facts: [Vxpipe.Calls.CallFact.t()],
          variable_snapshots: Vxpipe.Calls.VariableSnapshotHistory.t(),
          artifacts: [Vxpipe.Calls.CallArtifact.t()],
          usage_observations: [Vxpipe.CallEngine.Usage.Observation.t()],
          usage_amounts: [Vxpipe.CallEngine.Usage.EffectiveAmount.t()],
          telephony_legs: [struct()]
        }
end
