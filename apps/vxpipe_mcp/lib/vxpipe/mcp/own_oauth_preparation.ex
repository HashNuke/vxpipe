defmodule Vxpipe.MCP.OwnOAuthPreparation do
  @moduledoc "Fresh discovery and registered-client preparation without registration side effects."
  alias Vxpipe.MCP.{
    DiscoveryIO,
    OAuthAuthorization,
    OAuthMetadata,
    OAuthPreparation,
    OwnOAuthConfiguration,
    ResourceMetadata,
    StaticConfiguration
  }

  def prepare(input, origin, options) do
    with {:ok, configuration} <- configuration(input, origin, options),
         :ok <- browser_grant(configuration),
         {:ok, authorization} <-
           OAuthAuthorization.build(
             configuration.metadata,
             configuration.token_request.client_id,
             configuration.authorization_context
           ) do
      request = configuration.token_request

      {:ok,
       %OAuthPreparation{
         authorization: authorization,
         client: %{
           client_id: request.client_id,
           auth_method: request.auth_method,
           client_secret: request[:client_secret],
           client_secret_expires_at: nil
         },
         token_endpoint: request.token_endpoint,
         draft_revision: input["revision"],
         issuer_response_required: true,
         extra_secrets: configuration.secrets
       }}
    end
  end

  def configuration(input, origin, options) do
    with :ok <- input(input),
         {:ok, resource} <- resource(input, DiscoveryIO.options(options)),
         {:ok, issuer} <- issuer(resource["authorization_servers"], input["issuer"]),
         {:ok, metadata} <- OAuthMetadata.discover(issuer, DiscoveryIO.options(options)),
         do: OwnOAuthConfiguration.new(input, metadata, resource, origin)
  end

  defp input(
         %{
           "endpoint" => endpoint,
           "auth_method" => "own_client",
           "revision" => revision,
           "credentials" => credentials
         } = input
       )
       when is_binary(revision) and byte_size(revision) in 1..128 and is_map(credentials) do
    with true <- Map.keys(input) -- ~w(endpoint auth_method revision credentials issuer) == [],
         {:ok, _} <- StaticConfiguration.endpoint(endpoint),
         do: :ok,
         else: (_ -> {:error, :invalid_own_oauth_configuration})
  end

  defp input(_), do: {:error, :invalid_own_oauth_configuration}

  defp resource(input, options) do
    case ResourceMetadata.discover(input["endpoint"], options) do
      {:error, :resource_metadata_missing} -> explicit_resource(input)
      result -> result
    end
  end

  defp explicit_resource(%{"endpoint" => endpoint, "issuer" => issuer}) when is_binary(issuer),
    do: {:ok, %{"resource" => endpoint, "authorization_servers" => [issuer]}}

  defp explicit_resource(_), do: {:error, :oauth_issuer_required}

  defp issuer([issuer], nil), do: {:ok, issuer}
  defp issuer(_issuers, nil), do: {:error, :oauth_issuer_required}

  defp issuer(issuers, selected) do
    if selected in issuers, do: {:ok, selected}, else: {:error, :invalid_oauth_issuer}
  end

  defp browser_grant(%OwnOAuthConfiguration{grant_type: "authorization_code"}), do: :ok
  defp browser_grant(_), do: {:error, :oauth_browser_grant_required}
end
