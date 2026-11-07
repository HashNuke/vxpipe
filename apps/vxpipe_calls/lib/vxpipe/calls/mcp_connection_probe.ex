defmodule Vxpipe.Calls.MCPConnectionProbe do
  @moduledoc """
  Read-only connection validation port. Implementations initialize an isolated MCP
  session and discover a bounded catalog, without invoking tools or saving records.
  Secrets travel only in an opaque private snapshot. All transient resources must
  be released on completion, timeout and caller cancellation.
  """
  @callback check(term(), String.t(), map()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPConnection.t()} | {:error, term()}

  @doc "Resolves credentialless endpoint/listing identity before duplicate lookup, without MCP or OAuth work."
  @callback resolve_target(term(), String.t(), map()) :: {:ok, map()} | {:error, atom()}

  @doc "Checks a new connection using the accepted target without another directory lookup."
  @callback check_target(term(), String.t(), map(), map()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPConnection.t()} | {:error, term()}

  @doc "Checks credentials against an accepted snapshot loaded from the tenant record, never browser input."
  @callback check_saved(term(), String.t(), map(), map()) ::
              {:ok, Vxpipe.Calls.ResolvedMCPConnection.t()} | {:error, term()}
end
