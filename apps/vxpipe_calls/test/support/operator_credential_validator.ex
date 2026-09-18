defmodule Vxpipe.Calls.TestOperatorCredentialValidator do
  @behaviour Vxpipe.Calls.ProviderCredentialValidator

  def validator(owner, result), do: {__MODULE__, {owner, result}}

  @impl true
  def validate({owner, result}, provider, auth_kind, payload) do
    send(owner, {:operator_credential_validated, provider, auth_kind, payload})
    result
  end
end
