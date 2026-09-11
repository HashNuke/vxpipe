defmodule Vxpipe.CallEngine.Telephony.LegReference do
  @moduledoc "Correlates one Vxpipe leg with its provider command identity."

  @enforce_keys [:leg_id, :provider_call_control_id]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          leg_id: String.t(),
          provider_call_control_id: String.t()
        }
end
