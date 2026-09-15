defmodule Vxpipe.Calls.ResolvedProviderCredential do
  @moduledoc "Private credential snapshot for a bounded provider activation. Never persist in a call plan."

  @derive {Inspect, only: [:credential]}
  @enforce_keys [:credential, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{credential: Vxpipe.Calls.ProviderCredential.t(), payload: map()}
end
