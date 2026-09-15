defmodule Vxpipe.Calls.ResolvedTelephonyService do
  @moduledoc "Private service and credential snapshot. Never persist in a definition or call plan."

  @derive {Inspect, only: [:service]}
  @enforce_keys [:service, :credential]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          service: Vxpipe.Calls.TelephonyService.t(),
          credential: Vxpipe.Calls.ResolvedProviderCredential.t()
        }
end
