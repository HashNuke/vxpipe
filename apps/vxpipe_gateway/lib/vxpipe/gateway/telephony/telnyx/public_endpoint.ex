defmodule Vxpipe.Gateway.Telephony.Telnyx.PublicEndpoint do
  @moduledoc false

  alias Vxpipe.Gateway.Telephony.ConfiguredService

  @spec event_url(ConfiguredService.t()) :: String.t()
  def event_url(
        %ConfiguredService{
          identity: %{service_reference: %{credential_name: "telnyx", credential_owner: owner}}
        } = service
      )
      when not is_nil(owner) do
    scoped_event_url(service.public_base_url, owner)
  end

  @doc "Builds a credential-scope URL, preserving the configured public path prefix."
  def scoped_event_url(base, owner) do
    suffix =
      case owner do
        :platform -> "/webhooks/platform/telnyx"
        {:tenant, key} -> "/webhooks/tenants/#{URI.encode(key, &URI.char_unreserved?/1)}/telnyx"
      end

    uri = URI.parse(base)
    URI.to_string(%{uri | path: String.trim_trailing(uri.path || "", "/") <> suffix})
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
