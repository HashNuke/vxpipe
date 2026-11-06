defmodule Vxpipe.MCP.OAuthRegistration do
  @moduledoc "Explicit Connect-time CIMD/DCR registration with installation-owned metadata."
  alias ExMCP.Authorization.{ClientRegistration, OIDCDiscovery, SecureHTTP}
  alias Vxpipe.MCP.{ClientMetadata, OAuthCapabilities}
  @derive {Inspect, only: []}
  defstruct [:client_id, :client_secret, :client_secret_expires_at, :auth_method]

  @methods [
    {"none", :none},
    {"client_secret_basic", :client_secret_basic},
    {"client_secret_post", :client_secret_post}
  ]

  def register(method, metadata, origin, initial_token, options \\ []) do
    with {:ok, document} <- ClientMetadata.document(origin),
         :ok <- OIDCDiscovery.validate_metadata(metadata, metadata["issuer"]),
         :ok <- OAuthCapabilities.validate(metadata) do
      register_client(method, metadata, document, initial_token, options)
    else
      _ -> {:error, :invalid_oauth_registration}
    end
  rescue
    _ -> {:error, :invalid_oauth_registration}
  end

  @doc "Reuses only a server-resolved DCR identity bound to this issuer, resource and callback."
  def reuse(saved, metadata, origin, resource, scopes) when is_map(saved) do
    supported =
      Map.get(metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

    with {:ok, document} <- ClientMetadata.document(origin),
         true <- saved["registration_method"] == "dcr",
         true <- saved["issuer"] == metadata["issuer"] and saved["resource"] == resource,
         true <- reusable_scopes?(saved["scopes"], scopes),
         true <- document.redirect_uris == [saved["redirect_uri"]],
         {method, auth} <-
           Enum.find(@methods, fn {method, _} -> method == saved["auth_method"] end),
         true <- is_list(supported) and method in supported,
         true <- text?(saved["client_id"]),
         true <- reusable_secret?(saved, auth) do
      {:ok,
       %__MODULE__{
         client_id: saved["client_id"],
         auth_method: auth,
         client_secret: saved["client_secret"],
         client_secret_expires_at: saved["client_secret_expires_at"]
       }}
    else
      _ -> :unavailable
    end
  end

  def reuse(_, _, _, _, _), do: :unavailable

  defp reusable_scopes?(saved, requested) do
    OAuthCapabilities.valid_scopes?(saved) and OAuthCapabilities.valid_scopes?(requested) and
      MapSet.subset?(MapSet.new(requested), MapSet.new(saved))
  end

  defp reusable_secret?(saved, :none), do: is_nil(saved["client_secret"])

  defp reusable_secret?(saved, _auth) do
    text?(saved["client_secret"]) and is_integer(saved["client_secret_expires_at"]) and
      secret_unexpired?(saved["client_secret_expires_at"])
  end

  @doc "Checks known client-secret lifetime; nil denotes unknown legacy/manual expiry."
  def secret_unexpired?(expiry, now \\ System.os_time(:second))
  def secret_unexpired?(nil, _now), do: true
  def secret_unexpired?(0, _now), do: true
  def secret_unexpired?(expiry, now) when is_integer(expiry), do: expiry > now
  def secret_unexpired?(_, _now), do: false

  defp register_client(:cimd, metadata, document, nil, _options) do
    if OAuthCapabilities.cimd_supported?(metadata) do
      {:ok, %__MODULE__{client_id: document.client_id, auth_method: :none}}
    else
      {:error, :oauth_registration_unavailable}
    end
  end

  defp register_client(:dcr, metadata, document, initial_token, options) do
    endpoint = metadata["registration_endpoint"]
    scopes = Keyword.get(options, :scopes, [])

    with {:ok, _} <- Vxpipe.MCP.StaticConfiguration.endpoint(endpoint),
         {method, auth} <- choose_auth(metadata),
         {:ok, headers} <- headers(initial_token),
         {:ok, document} <- registration_document(document, metadata, scopes),
         {:ok, body} <-
           ClientRegistration.build_request(
             document
             |> Map.delete(:client_id)
             |> Map.merge(%{
               registration_endpoint: endpoint,
               application_type: "web",
               token_endpoint_auth_method: method
             })
           ) do
      body = if scopes == [], do: Map.delete(body, :scope), else: body

      case SecureHTTP.request(:post, endpoint, headers, JSON.encode!(body), http_options(options)) do
        {:ok, {{_, 201, _}, _, encoded}} ->
          parse(encoded, document.redirect_uris, method, auth, scopes)

        _ ->
          {:error, :oauth_registration_failed}
      end
    else
      _ -> {:error, :oauth_registration_unavailable}
    end
  end

  defp register_client(_, _, _, _, _), do: {:error, :oauth_registration_unavailable}

  defp registration_document(document, metadata, scopes) do
    supported = Map.get(metadata, "grant_types_supported", ["authorization_code", "implicit"])
    grants = Enum.filter(document.grant_types, &(&1 in supported))

    if "authorization_code" in grants and OAuthCapabilities.valid_scopes?(scopes),
      do: {:ok, %{document | grant_types: grants} |> Map.put(:scope, Enum.join(scopes, " "))},
      else: {:error, :oauth_registration_unavailable}
  end

  defp choose_auth(metadata) do
    supported =
      Map.get(metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

    if is_list(supported), do: Enum.find(@methods, fn {method, _} -> method in supported end)
  end

  defp headers(nil),
    do: {:ok, [{"content-type", "application/json"}, {"accept", "application/json"}]}

  defp headers(token) when is_binary(token) and byte_size(token) in 1..8192 do
    if Regex.match?(~r/\A[A-Za-z0-9._~+\/-]+=*\z/, token) do
      {:ok, headers} = headers(nil)
      {:ok, [{"authorization", "Bearer " <> token} | headers]}
    else
      {:error, :invalid_initial_access_token}
    end
  end

  defp headers(_), do: {:error, :invalid_initial_access_token}

  defp parse(encoded, redirects, method, auth, scopes) do
    with {:ok, data} when is_map(data) <- JSON.decode(encoded),
         true <- text?(data["client_id"]),
         true <- data["redirect_uris"] == redirects,
         true <- Map.get(data, "token_endpoint_auth_method", "client_secret_basic") == method,
         true <- registered_flow?(data, scopes),
         true <- auth == :none or text?(data["client_secret"]),
         true <- issued_secret_valid?(data) do
      {:ok,
       %__MODULE__{
         client_id: data["client_id"],
         auth_method: auth,
         client_secret: if(auth == :none, do: nil, else: data["client_secret"]),
         client_secret_expires_at:
           if(auth == :none, do: nil, else: data["client_secret_expires_at"])
       }}
    else
      _ -> {:error, :invalid_oauth_registration}
    end
  end

  defp registered_flow?(data, scopes) do
    capabilities = %{
      "grant_types_supported" => Map.get(data, "grant_types", ["authorization_code"]),
      "response_types_supported" => Map.get(data, "response_types", ["code"])
    }

    OAuthCapabilities.validate(capabilities) == :ok and
      "authorization_code" in capabilities["grant_types_supported"] and
      "code" in capabilities["response_types_supported"] and registered_scopes?(data, scopes)
  end

  defp registered_scopes?(data, requested) do
    case Map.fetch(data, "scope") do
      :error ->
        true

      {:ok, value} when is_binary(value) and byte_size(value) <= 16_384 ->
        scopes = String.split(value, " ")

        OAuthCapabilities.valid_scopes?(scopes) and
          MapSet.subset?(MapSet.new(requested), MapSet.new(scopes))

      _ ->
        false
    end
  end

  defp issued_secret_valid?(data) do
    if Map.has_key?(data, "client_secret") do
      text?(data["client_secret"]) and is_integer(data["client_secret_expires_at"]) and
        secret_unexpired?(data["client_secret_expires_at"])
    else
      true
    end
  end

  defp text?(value), do: is_binary(value) and byte_size(value) in 1..8192 and String.valid?(value)

  defp http_options(options) do
    options
    |> Keyword.take([:dns_resolver, :request_fun])
    |> Keyword.merge(
      allow_insecure_loopback: false,
      allowed_private_hosts: [],
      ssl_options: [],
      max_request_bytes: 65_536,
      max_response_bytes: 65_536,
      max_header_bytes: 16_384,
      dns_timeout_ms: 1000,
      connect_timeout_ms: 2000,
      request_timeout_ms: 5000
    )
  end
end
