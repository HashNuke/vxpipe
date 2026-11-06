defmodule Vxpipe.MCP.OAuthPreparation do
  @moduledoc "Fresh Connect-time discovery and managed registration; result must be persisted before browser handoff."
  alias Vxpipe.MCP.{
    ClientMetadata,
    DiscoveryIO,
    OAuthAuthorization,
    OAuthMetadata,
    OAuthRegistration,
    OAuthRequestParameters,
    ResourceMetadata,
    StaticConfiguration
  }

  @derive {Inspect, only: []}
  defstruct [
    :authorization,
    :client,
    :token_endpoint,
    :draft_revision,
    :issuer_response_required,
    :extra_secrets
  ]

  def prepare(input, origin, options \\ [])

  def prepare(%{"auth_method" => "own_client"} = input, origin, options),
    do: Vxpipe.MCP.OwnOAuthPreparation.prepare(input, origin, options)

  def prepare(input, origin, options) do
    with :ok <- input(input),
         {:ok, document} <- ClientMetadata.document(origin),
         {:ok, _} <- StaticConfiguration.endpoint(input["endpoint"]),
         {:ok, resource} <-
           ResourceMetadata.discover(input["endpoint"], DiscoveryIO.options(options)),
         {:ok, issuer} <- issuer(resource["authorization_servers"], input["issuer"]),
         {:ok, metadata} <- OAuthMetadata.discover(issuer, DiscoveryIO.options(options)),
         {:ok, _token_query} <- OAuthRequestParameters.endpoint_query(metadata["token_endpoint"]),
         context = %{
           origin: origin,
           resource: resource["resource"],
           scopes: ResourceMetadata.authorization_scopes(resource)
         },
         {:ok, _validated} <- OAuthAuthorization.build(metadata, document.client_id, context),
         {:ok, client} <-
           client(
             input,
             metadata,
             origin,
             resource["resource"],
             Keyword.put(options, :scopes, context.scopes)
           ),
         {:ok, authorization} <- OAuthAuthorization.build(metadata, client.client_id, context) do
      {:ok,
       %__MODULE__{
         authorization: authorization,
         client: client,
         token_endpoint: metadata["token_endpoint"],
         draft_revision: input["revision"],
         issuer_response_required:
           Map.get(metadata, "authorization_response_iss_parameter_supported", false)
       }}
    end
  end

  defp client(input, metadata, origin, resource, options) do
    reused =
      if input["auth_method"] == "dcr" and is_nil(input["initial_access_token"]),
        do:
          OAuthRegistration.reuse(
            Keyword.get(options, :registration),
            metadata,
            origin,
            resource,
            Keyword.fetch!(options, :scopes)
          ),
        else: :unavailable

    case reused do
      {:ok, client} ->
        {:ok, client}

      :unavailable ->
        OAuthRegistration.register(
          method(input["auth_method"]),
          metadata,
          origin,
          input["initial_access_token"],
          options
        )
    end
  end

  defp input(%{"endpoint" => endpoint, "revision" => revision, "auth_method" => method} = input)
       when is_binary(endpoint) and is_binary(revision) and byte_size(revision) in 1..128 and
              method in ["cimd", "dcr"] do
    if Map.keys(input) -- ~w(endpoint revision auth_method issuer initial_access_token) == [] and
         String.valid?(revision) and
         (not Map.has_key?(input, "issuer") or is_binary(input["issuer"])) and
         (not Map.has_key?(input, "initial_access_token") or
            (method == "dcr" and is_binary(input["initial_access_token"]) and
               byte_size(input["initial_access_token"]) in 1..8192)),
       do: :ok,
       else: {:error, :invalid_oauth_preparation}
  end

  defp input(_), do: {:error, :invalid_oauth_preparation}
  defp method("cimd"), do: :cimd
  defp method("dcr"), do: :dcr
  defp issuer([issuer], nil), do: {:ok, issuer}
  defp issuer(_, nil), do: {:error, :oauth_issuer_required}

  defp issuer(issuers, selected) do
    if selected in issuers, do: {:ok, selected}, else: {:error, :invalid_oauth_issuer}
  end
end
