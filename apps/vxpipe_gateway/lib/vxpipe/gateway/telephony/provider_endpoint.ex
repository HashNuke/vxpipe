defmodule Vxpipe.Gateway.Telephony.ProviderEndpoint do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService
  alias Vxpipe.Providers.Telnyx.PublicEndpoint, as: TelnyxEndpoint
  alias Vxpipe.Gateway.Telephony.Twilio.PublicEndpoint, as: TwilioEndpoint

  @spec event_url(ConfiguredService.t(), String.t()) :: String.t()
  def event_url(%ConfiguredService{identity: %{provider: :telnyx}} = service, _leg_id) do
    TelnyxEndpoint.event_url(service)
  end

  def event_url(%ConfiguredService{identity: %{provider: :twilio}} = service, leg_id) do
    TwilioEndpoint.event_url(service, leg_id)
  end

  @spec media_url(ConfiguredService.t(), String.t()) :: String.t()
  def media_url(%ConfiguredService{identity: %{provider: :telnyx}} = service, token) do
    TelnyxEndpoint.media_url(service, token)
  end

  def media_url(%ConfiguredService{identity: %{provider: :twilio}} = service, token) do
    TwilioEndpoint.media_url(service, token)
  end
end
