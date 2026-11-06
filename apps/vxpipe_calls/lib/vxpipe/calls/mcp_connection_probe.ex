defmodule Vxpipe.Calls.MCPConnectionProbe do
  @moduledoc """
  Read-only connection validation port. Implementations initialize an isolated MCP
  session and discover a bounded catalog, without invoking tools or saving records.
  Secrets travel only in an opaque private snapshot. All transient resources must
  be released on completion, timeout and caller cancellation.
  """
  @callback check(term(), String.t(), map()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPConnection.t()} | {:error, term()}
end
