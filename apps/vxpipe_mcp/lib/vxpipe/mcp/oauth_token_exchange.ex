defmodule Vxpipe.MCP.OAuthTokenExchange do
  @moduledoc "Single-attempt OAuth token grants through ExMCP's pinned HTTP boundary."
  alias ExMCP.Authorization.SecureHTTP

  alias Vxpipe.MCP.{
    Authentication,
    OAuthClientAssertion,
    OAuthRequestParameters,
    StaticConfiguration
  }

  @derive {Inspect, only: []}
  defstruct [:access_token, :refresh_token, :expires_in, :scope, token_type: "Bearer"]

  @keys ~w(token_endpoint client_id client_secret client_secret_expires_at client_assertion auth_method code code_verifier redirect_uri resource parameters audience)a

  def exchange(request, options \\ []) do
    with :ok <- validate(request) do
      body = [
        grant_type: "authorization_code",
        code: request.code,
        code_verifier: request.code_verifier,
        redirect_uri: request.redirect_uri,
        resource: request.resource,
        client_id: request.client_id
      ]

      send_request(request, body, options)
    end
  rescue
    _ -> {:error, :oauth_token_exchange_failed}
  end

  def refresh(request, options \\ []) do
    with :ok <- validate_refresh(request) do
      body = [
        grant_type: "refresh_token",
        refresh_token: request.refresh_token,
        client_id: request.client_id,
        resource: request.resource
      ]

      send_request(request, body, options)
    end
  rescue
    _ -> {:error, :oauth_token_exchange_failed}
  end

  def client_credentials(request, metadata, options \\ []) do
    with :ok <- validate_client_credentials(request, metadata) do
      body = [
        grant_type: "client_credentials",
        client_id: request.client_id,
        resource: request.resource
      ]

      body = if request[:scope], do: Keyword.put(body, :scope, request.scope), else: body

      with {:ok, token} <- send_request(request, body, options),
           do: {:ok, %{token | refresh_token: nil}}
    end
  rescue
    _ -> {:error, :oauth_token_exchange_failed}
  end

  defp validate_client_credentials(request, metadata) when is_map(request) and is_map(metadata) do
    method = request[:auth_method]

    with true <- method in [:client_secret_basic, :client_secret_post, :private_key_jwt],
         true <- "client_credentials" in Map.get(metadata, "grant_types_supported", []),
         true <-
           Atom.to_string(method) in Map.get(metadata, "token_endpoint_auth_methods_supported", [
             "client_secret_basic"
           ]),
         true <- request[:token_endpoint] == metadata["token_endpoint"],
         true <- signing_supported?(request, metadata),
         true <-
           Map.keys(request) --
             ~w(token_endpoint client_id client_secret client_secret_expires_at client_assertion auth_method resource scope parameters audience)a ==
             [],
         true <- text?(request[:client_id], 2048) and credentials?(request),
         true <- scope?(request[:scope]),
         {:ok, _} <- StaticConfiguration.endpoint(request[:token_endpoint]),
         {:ok, _} <- StaticConfiguration.endpoint(request[:resource]) do
      :ok
    else
      _ -> {:error, :invalid_oauth_client_credentials}
    end
  end

  defp validate_client_credentials(_, _), do: {:error, :invalid_oauth_client_credentials}
  defp scope?(nil), do: true

  defp scope?(value) when is_binary(value) and byte_size(value) in 1..16_384,
    do: Regex.match?(~r/\A[\x21\x23-\x5B\x5D-\x7E]+(?: [\x21\x23-\x5B\x5D-\x7E]+)*\z/, value)

  defp scope?(_), do: false

  defp validate_refresh(request) when is_map(request) do
    with true <-
           Map.keys(request) --
             ~w(token_endpoint client_id client_secret client_secret_expires_at client_assertion auth_method refresh_token resource parameters audience)a ==
             [],
         true <-
           request[:auth_method] in [
             :none,
             :client_secret_basic,
             :client_secret_post,
             :private_key_jwt
           ],
         true <- text?(request[:client_id], 2048) and text?(request[:refresh_token], 32_768),
         true <- credentials?(request),
         {:ok, _} <- StaticConfiguration.endpoint(request[:token_endpoint]),
         {:ok, _} <- StaticConfiguration.endpoint(request[:resource]) do
      :ok
    else
      _ -> {:error, :invalid_oauth_token_request}
    end
  end

  defp validate_refresh(_), do: {:error, :invalid_oauth_token_request}

  defp validate(request) when is_map(request) do
    with true <- Map.keys(request) -- @keys == [],
         true <-
           request[:auth_method] in [
             :none,
             :client_secret_basic,
             :client_secret_post,
             :private_key_jwt
           ],
         true <- text?(request[:client_id], 2048) and text?(request[:code], 8192),
         true <- verifier?(request[:code_verifier]),
         true <- credentials?(request),
         {:ok, _} <- StaticConfiguration.endpoint(request[:token_endpoint]),
         {:ok, _} <- StaticConfiguration.endpoint(request[:redirect_uri]),
         {:ok, _} <- StaticConfiguration.endpoint(request[:resource]) do
      :ok
    else
      _ -> {:error, :invalid_oauth_token_request}
    end
  end

  defp validate(_), do: {:error, :invalid_oauth_token_request}

  defp credentials?(%{auth_method: :none} = request),
    do:
      not Map.has_key?(request, :client_secret) and
        not Map.has_key?(request, :client_secret_expires_at) and
        not Map.has_key?(request, :client_assertion)

  defp credentials?(
         %{auth_method: :private_key_jwt, client_assertion: %OAuthClientAssertion{} = signing} =
           request
       ),
       do:
         signing.client_id == request[:client_id] and
           signing.token_endpoint == request[:token_endpoint] and
           not Map.has_key?(request, :client_secret) and
           not Map.has_key?(request, :client_secret_expires_at)

  defp credentials?(%{auth_method: :private_key_jwt}), do: false

  defp credentials?(request),
    do:
      text?(request[:client_secret], 8192) and
        not Map.has_key?(request, :client_assertion) and
        Vxpipe.MCP.OAuthRegistration.secret_unexpired?(request[:client_secret_expires_at])

  defp signing_supported?(
         %{auth_method: :private_key_jwt, client_assertion: %OAuthClientAssertion{} = signing},
         metadata
       ) do
    algorithms = metadata["token_endpoint_auth_signing_alg_values_supported"]
    is_list(algorithms) and signing.algorithm in algorithms
  end

  defp signing_supported?(%{auth_method: :private_key_jwt}, _metadata), do: false
  defp signing_supported?(_request, _metadata), do: true

  defp send_request(request, body, options) do
    with {:ok, parameters} <-
           OAuthRequestParameters.validate(Map.get(request, :parameters, []), request[:audience]),
         {:ok, endpoint_query} <- OAuthRequestParameters.endpoint_query(request.token_endpoint),
         false <- Enum.any?(Map.keys(parameters), &Map.has_key?(endpoint_query, &1)),
         {:ok, headers, body} <- authenticate(request, body) do
      headers = [
        {"content-type", "application/x-www-form-urlencoded"},
        {"accept", "application/json"} | headers
      ]

      SecureHTTP.request(
        :post,
        request.token_endpoint,
        headers,
        URI.encode_query(body ++ Map.to_list(parameters)),
        http_options(options)
      )
      |> result()
    else
      true -> {:error, :invalid_oauth_parameters}
      {:error, _} = error -> error
    end
  end

  defp authenticate(%{auth_method: :none}, body), do: {:ok, [], body}

  defp authenticate(%{auth_method: :private_key_jwt, client_assertion: signing}, body) do
    with {:ok, parameters} <- OAuthClientAssertion.parameters(signing),
         do: {:ok, [], Keyword.delete(body, :client_id) ++ parameters}
  end

  defp authenticate(%{auth_method: :client_secret_basic} = request, body) do
    encoded =
      URI.encode_www_form(request.client_id) <> ":" <> URI.encode_www_form(request.client_secret)

    {:ok, [{"authorization", "Basic " <> Base.encode64(encoded)}],
     Keyword.delete(body, :client_id)}
  end

  defp authenticate(request, body),
    do: {:ok, [], Keyword.put(body, :client_secret, request.client_secret)}

  defp verifier?(value) when is_binary(value) and byte_size(value) in 43..128,
    do: Regex.match?(~r/\A[A-Za-z0-9._~-]+\z/, value)

  defp verifier?(_), do: false

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

  defp result({:ok, {{_, 200, _}, _, encoded}}) do
    with {:ok, token} when is_map(token) <- JSON.decode(encoded),
         {:ok, _headers} <- Authentication.headers(type: :bearer, token: token["access_token"]),
         type when is_binary(type) <- token["token_type"],
         true <- String.downcase(type) == "bearer",
         true <- is_nil(token["refresh_token"]) or text?(token["refresh_token"], 32_768),
         true <-
           is_nil(token["expires_in"]) or
             (is_integer(token["expires_in"]) and token["expires_in"] > 0),
         true <- scope?(token["scope"]) do
      {:ok,
       %__MODULE__{
         access_token: token["access_token"],
         refresh_token: token["refresh_token"],
         expires_in: token["expires_in"],
         scope: token["scope"]
       }}
    else
      _ -> {:error, :invalid_oauth_token_response}
    end
  end

  defp result({:ok, {{_, status, _}, _, encoded}}) when status in 400..499 do
    case JSON.decode(encoded) do
      {:ok, %{"error" => "invalid_grant"}} -> {:error, :oauth_grant_rejected}
      _ -> {:error, :oauth_token_exchange_failed}
    end
  end

  defp result(_), do: {:error, :oauth_token_exchange_failed}

  defp text?(value, max),
    do: is_binary(value) and byte_size(value) in 1..max and String.valid?(value)
end
