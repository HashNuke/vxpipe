defmodule Vxpipe.Providers.Google do
  @moduledoc "Google AI Studio's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "google"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Google.Credential,
      credential_validation: Vxpipe.Providers.Google.CredentialValidation
    }
  end
end
