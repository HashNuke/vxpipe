defmodule Vxpipe.Providers.Jev do
  @moduledoc "Jev's declared Vxpipe capabilities (System One decisions)."

  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "jev"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Jev.Credential,
      credential_validation: Vxpipe.Providers.Jev.CredentialValidation,
      decisions: Vxpipe.Providers.Jev.Decisions
    }
  end
end
