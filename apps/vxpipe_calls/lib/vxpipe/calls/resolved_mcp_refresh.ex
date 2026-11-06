defmodule Vxpipe.Calls.ResolvedMCPRefresh do
  @moduledoc "Private durable refresh claim; never serialize or log credentials."
  @derive {Inspect, only: []}
  @enforce_keys [:id, :grant_revision, :secrets]
  defstruct @enforce_keys
end
