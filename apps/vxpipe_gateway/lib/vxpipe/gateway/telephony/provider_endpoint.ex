defmodule Vxpipe.Gateway.Telephony.ProviderEndpoint do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint, as: TelnyxEndpoint
  alias Vxpipe.Gateway.Telephony.Twilio.PublicEndpoint, as: TwilioEndpoint

  @spec media_url(ConfiguredService.t(), String.t()) :: String.t()
  def media_url(%ConfiguredService{identity: %{provider: :telnyx}} = service, token) do
    TelnyxEndpoint.media_url(service, token)
  end

  def media_url(%ConfiguredService{identity: %{provider: :twilio}} = service, token) do
    TwilioEndpoint.media_url(service, token)
  end
end
