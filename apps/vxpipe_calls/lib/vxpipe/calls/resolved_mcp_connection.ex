defmodule Vxpipe.Calls.ResolvedMCPConnection do
  @moduledoc "Private MCP credentials for a bounded activation. Never put this value in a call plan."

  @derive {Inspect, only: []}
  @enforce_keys [:connection, :secrets]
  defstruct @enforce_keys

  @type t :: %__MODULE__{connection: map(), secrets: map()}
end
