defmodule Vxpipe.Providers.Telnyx do
  @moduledoc "Telnyx's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "telnyx"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Telnyx.Credential,
      credential_validation: Vxpipe.Providers.Telnyx.CredentialValidation,
      telephony: Vxpipe.Providers.Telnyx.ServiceProfile
    }
  end
end
