defmodule Vxpipe.MCP.OAuthAuthorization do
  @moduledoc "Builds a private S256 authorization request for a Console-owned durable attempt."
  alias ExMCP.Authorization.{OIDCDiscovery, PKCE}
  alias Vxpipe.MCP.{ClientMetadata, OAuthRequestParameters, StaticConfiguration}

  @derive {Inspect, only: []}
  @enforce_keys [
    :authorization_url,
    :state,
    :code_verifier,
    :issuer,
    :redirect_uri,
    :resource,
    :client_id,
    :scopes
  ]
  defstruct @enforce_keys

  def build(metadata, client_id, %{origin: origin, resource: resource, scopes: scopes} = context)
      when is_map(metadata) and is_binary(client_id) and byte_size(client_id) in 1..2048 do
    with true <- Map.keys(context) -- [:origin, :resource, :scopes, :parameters, :audience] == [],
         {:ok, parameters} <-
           OAuthRequestParameters.validate(Map.get(context, :parameters, []), context[:audience]),
         {:ok, client_metadata} <- ClientMetadata.document(origin),
         {:ok, _resource} <- StaticConfiguration.endpoint(resource),
         true <- scopes?(scopes),
         :ok <- OIDCDiscovery.validate_metadata(metadata, metadata["issuer"]),
         :ok <- validate_capabilities(metadata),
         {:ok, endpoint} <- authorization_endpoint(metadata["authorization_endpoint"]),
         {:ok, endpoint_query} <-
           OAuthRequestParameters.endpoint_query(metadata["authorization_endpoint"]),
         false <- Enum.any?(Map.keys(parameters), &Map.has_key?(endpoint_query, &1)) do
      [redirect_uri] = client_metadata.redirect_uris
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      verifier = PKCE.generate_code_verifier()

      query =
        endpoint_query
        |> Map.merge(parameters)
        |> Map.merge(%{
          "response_type" => "code",
          "client_id" => client_id,
          "redirect_uri" => redirect_uri,
          "scope" => Enum.join(scopes, " "),
          "state" => state,
          "resource" => resource,
          "code_challenge" => PKCE.generate_code_challenge(verifier),
          "code_challenge_method" => "S256"
        })

      {:ok,
       %__MODULE__{
         authorization_url: URI.to_string(%{endpoint | query: URI.encode_query(query)}),
         state: state,
         code_verifier: verifier,
         issuer: metadata["issuer"],
         redirect_uri: redirect_uri,
         resource: resource,
         client_id: client_id,
         scopes: scopes
       }}
    else
      {:error, :unsupported_oauth_capabilities} = error -> error
      _invalid -> {:error, :invalid_oauth_authorization}
    end
  rescue
    _invalid -> {:error, :invalid_oauth_authorization}
  end

  def build(_metadata, _client_id, _context), do: {:error, :invalid_oauth_authorization}

  @doc "Validates the shared-callback authorization-code security profile before side effects."
  defdelegate validate_capabilities(metadata),
    to: Vxpipe.MCP.OAuthCapabilities,
    as: :authorization_code

  defp authorization_endpoint(url) do
    with {:ok, _validated} <- StaticConfiguration.endpoint(url),
         {:ok, uri} <- URI.new(url),
         do: {:ok, uri}
  end

  defp scopes?(scopes) when is_list(scopes) and length(scopes) <= 64 do
    Enum.all?(scopes, fn scope ->
      is_binary(scope) and byte_size(scope) in 1..256 and
        Enum.all?(:binary.bin_to_list(scope), &(&1 == 33 or &1 in 35..91 or &1 in 93..126))
    end)
  end

  defp scopes?(_scopes), do: false
end
