defmodule Vxpipe.MCP.OAuthMetadata do
  @moduledoc "Read-only authorization metadata discovery for the approved MCP profile."
  alias ExMCP.Authorization.{EndpointPolicy, MetadataFetcher, OIDCDiscovery}
  alias Vxpipe.MCP.OAuthCapabilities

  @fields ~w(issuer authorization_endpoint token_endpoint registration_endpoint
    revocation_endpoint scopes_supported response_types_supported grant_types_supported
    code_challenge_methods_supported token_endpoint_auth_methods_supported
    token_endpoint_auth_signing_alg_values_supported
    client_id_metadata_document_supported authorization_response_iss_parameter_supported)

  def discover(issuer, options \\ []) do
    with {:ok, uri} <- issuer_uri(issuer) do
      fetch(urls(uri), issuer, fetch_options(options))
    end
  end

  defp issuer_uri(issuer) when is_binary(issuer) and byte_size(issuer) in 1..2048 do
    with {:ok, _endpoint} <- Vxpipe.MCP.StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil} = uri} <- URI.new(issuer) do
      {:ok, uri}
    else
      _invalid -> {:error, :invalid_oauth_issuer}
    end
  end

  defp issuer_uri(_issuer), do: {:error, :invalid_oauth_issuer}

  defp urls(uri) do
    path = String.trim_trailing(uri.path || "", "/")

    paths = [
      "/.well-known/oauth-authorization-server" <> path,
      "/.well-known/openid-configuration" <> path,
      path <> "/.well-known/openid-configuration"
    ]

    paths |> Enum.uniq() |> Enum.map(&URI.to_string(%{uri | path: &1}))
  end

  defp fetch([], _issuer, _options), do: {:error, :oauth_metadata_unavailable}

  defp fetch([url | rest], issuer, options) do
    case MetadataFetcher.fetch(url, options) do
      {:ok, %{status: 200, body: body}} -> validate(body, issuer, options)
      {:ok, %{status: status}} when status in [404, 405] -> fetch(rest, issuer, options)
      _failure -> {:error, :oauth_metadata_unavailable}
    end
  end

  defp validate(body, issuer, options) do
    with {:ok, %{"issuer" => ^issuer} = metadata} <- JSON.decode(body),
         :ok <- OAuthCapabilities.validate(metadata),
         :ok <- validate_endpoints(metadata, issuer, options) do
      {:ok, Map.take(metadata, @fields)}
    else
      _invalid -> {:error, :invalid_oauth_metadata}
    end
  end

  defp validate_endpoints(%{"grant_types_supported" => grants} = metadata, issuer, options)
       when is_list(grants) and length(grants) in 1..32 do
    if Enum.all?(grants, &is_binary/1) and
         not Enum.any?(grants, &(&1 in ["authorization_code", "implicit"])) do
      with {:ok, _} <- Vxpipe.MCP.StaticConfiguration.endpoint(metadata["token_endpoint"]),
           do: EndpointPolicy.validate_metadata(metadata, issuer, options)
    else
      OIDCDiscovery.validate_metadata(metadata, issuer, options)
    end
  end

  defp validate_endpoints(metadata, issuer, options),
    do: OIDCDiscovery.validate_metadata(metadata, issuer, options)

  defp fetch_options(options) do
    options
    |> Keyword.take([:dns_resolver, :http_client])
    |> Keyword.merge(
      max_redirects: 2,
      max_response_bytes: 65_536,
      max_aggregate_bytes: 131_072,
      dns_timeout_ms: 1_000,
      connect_timeout_ms: 2_000,
      request_timeout_ms: 3_000,
      allowed_redirect_origins: [],
      allow_insecure_loopback: false
    )
  end
end
