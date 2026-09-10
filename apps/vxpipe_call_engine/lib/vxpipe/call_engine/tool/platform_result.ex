defmodule Vxpipe.CallEngine.Tool.PlatformResult do
  @moduledoc false

  @derive {Inspect, only: [:effect]}
  @enforce_keys [:effect, :result]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          effect: :hangup | :participant_transfer_committed,
          result: term()
        }
end
