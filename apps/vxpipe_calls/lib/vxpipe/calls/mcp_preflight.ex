defmodule Vxpipe.Calls.MCPPreflight do
  @moduledoc """
  Trusted credentialless discovery port. Implementations bound the complete probe
  lifetime and concurrency, return only validated metadata tied to endpoint/revision,
  and never create connections, register clients, acquire tokens or invoke tools.
  Calls checks current tenant write authority before and after discovery.
  """
  @callback discover(term(), String.t(), map()) :: {:ok, map()} | {:error, atom()}
end
