defmodule Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @spec event_url(ConfiguredService.t()) :: String.t()
  def event_url(%ConfiguredService{} = service) do
    append_path(service, "events")
  end

  @spec media_url(ConfiguredService.t(), String.t()) :: String.t()
  def media_url(%ConfiguredService{} = service, token) when is_binary(token) do
    service
    |> append_path("media/#{token}")
    |> URI.parse()
    |> Map.put(:scheme, "wss")
    |> URI.to_string()
  end

  defp append_path(service, suffix) do
    base = URI.parse(service.public_base_url)

    path =
      (base.path || "") <>
        "/api/telephony/telnyx/#{service.identity.ingress_key}/#{suffix}"

    base
    |> Map.put(:path, path)
    |> URI.to_string()
  end
end
