defmodule Vxpipe.Providers.Twilio do
  @moduledoc "Twilio's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "twilio"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Twilio.Credential,
      credential_validation: Vxpipe.Providers.Twilio.CredentialValidation,
      telephony: Vxpipe.Providers.Twilio.ServiceProfile
    }
  end
end
