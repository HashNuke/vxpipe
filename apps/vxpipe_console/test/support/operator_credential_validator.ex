defmodule Vxpipe.Console.Test.OperatorCredentialValidator do
  @behaviour Vxpipe.Calls.ProviderCredentialValidator

  @impl true
  def validate({owner, result}, provider, auth_kind, payload) do
    send(owner, {:operator_credential_validated, provider, auth_kind, payload})
    result
  end
end
