defmodule Vxpipe.Calls.MCPOAuthPreparation do
  @moduledoc "Server-owned OAuth preparation port; new connections resolve public identity before protocol work."

  @callback resolve_target(term(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
  @callback prepare_target(term(), String.t(), map(), String.t(), map()) ::
              {:ok, Vxpipe.Calls.PreparedMCPOAuth.t()} | {:error, atom()}
  @callback prepare_reconnect(term(), String.t(), map(), String.t(), map()) ::
              {:ok, Vxpipe.Calls.PreparedMCPOAuth.t()} | {:error, atom()}
  @callback prepare_saved(term(), String.t(), map(), String.t(), map(), map()) ::
              {:ok, Vxpipe.Calls.PreparedMCPOAuth.t()} | {:error, atom()}
end
