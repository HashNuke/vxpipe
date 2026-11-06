defmodule Vxpipe.Calls.ResolvedMCPOAuthAttempt do
  @moduledoc "Private claimed outbound OAuth attempt. Never serialize into a public response."
  @derive {Inspect, only: []}
  @enforce_keys [:attempt, :secrets]
  defstruct @enforce_keys
  @type t :: %__MODULE__{attempt: map(), secrets: map()}
end
