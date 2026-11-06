defmodule Vxpipe.MCP.ResourceMetadata do
  @moduledoc "Read-only protected-resource discovery; missing metadata is never anonymous access."
  alias ExMCP.Authorization.MetadataFetcher
  alias Vxpipe.MCP.{AuthenticationChallenge, OAuthCapabilities, StaticConfiguration}

  def authorization_scopes(%{"challenge_scope" => scope}) when is_binary(scope),
    do: String.split(scope, " ", trim: true)

  def authorization_scopes(metadata), do: Map.get(metadata, "scopes_supported", [])

  def discover(endpoint, options \\ []) do
    options = fetch_options(options)

    with {:ok, _canonical} <- StaticConfiguration.endpoint(endpoint),
         {:ok, response} <- MetadataFetcher.fetch(endpoint, options),
         {:ok, challenge} <- challenge(response),
         {:ok, metadata} <- fetch(metadata_urls(endpoint, challenge), endpoint, options) do
      {:ok, Map.put(metadata, "challenge_scope", challenge["scope"])}
    else
      {:error, {:metadata_fetch_error, _reason}} -> {:error, :resource_metadata_unavailable}
      {:error, _reason} = error -> error
    end
  end

  defp challenge(%{status: 401, headers: headers}) do
    values = for {name, value} <- headers, String.downcase(name) == "www-authenticate", do: value
    parse_challenges(values)
  end

  defp challenge(_response), do: {:ok, %{}}

  defp parse_challenges(values) do
    if Enum.reduce(values, 0, &(byte_size(&1) + &2)) > 8192 do
      {:error, :invalid_resource_challenge}
    else
      bearer =
        for value <- values,
            {:bearer, params} <- AuthenticationChallenge.parse(value),
            do: params

      case bearer do
        [] -> {:ok, %{}}
        [params] -> unique_parameters(params)
        _ambiguous -> {:error, :invalid_resource_challenge}
      end
    end
  rescue
    _invalid -> {:error, :invalid_resource_challenge}
  end

  defp unique_parameters(params) do
    keys = Enum.map(params, &elem(&1, 0))

    parsed = Map.new(params)

    if length(Enum.uniq(keys)) == length(keys) and
         (not Map.has_key?(parsed, "scope") or OAuthCapabilities.challenge_scope?(parsed["scope"])),
       do: {:ok, parsed},
       else: {:error, :invalid_resource_challenge}
  end

  defp metadata_urls(_endpoint, %{"resource_metadata" => url}), do: [url]

  defp metadata_urls(endpoint, _challenge) do
    uri = URI.parse(endpoint)
    path = String.trim_trailing(uri.path || "", "/")

    ["/.well-known/oauth-protected-resource" <> path, "/.well-known/oauth-protected-resource"]
    |> Enum.uniq()
    |> Enum.map(&URI.to_string(%{uri | path: &1, query: nil}))
  end

  defp fetch([], _endpoint, _options), do: {:error, :resource_metadata_missing}

  defp fetch([url | rest], endpoint, options) do
    case MetadataFetcher.fetch(url, options) do
      {:ok, %{status: 200, body: body}} -> validate(body, endpoint)
      {:ok, %{status: 404}} -> fetch(rest, endpoint, options)
      _failure -> {:error, :resource_metadata_unavailable}
    end
  end

  defp validate(body, endpoint) do
    with {:ok, %{"resource" => ^endpoint, "authorization_servers" => issuers} = metadata} <-
           JSON.decode(body),
         true <- is_list(issuers) and length(issuers) in 1..8,
         true <- Enum.all?(issuers, &valid_issuer?/1),
         true <- length(Enum.uniq(issuers)) == length(issuers),
         true <- OAuthCapabilities.valid_scopes?(Map.get(metadata, "scopes_supported", [])) do
      {:ok, Map.take(metadata, ~w(resource authorization_servers scopes_supported))}
    else
      _invalid -> {:error, :invalid_resource_metadata}
    end
  end

  defp valid_issuer?(issuer) do
    with {:ok, _} <- StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil}} <- URI.new(issuer),
         do: true,
         else: (_ -> false)
  end

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
