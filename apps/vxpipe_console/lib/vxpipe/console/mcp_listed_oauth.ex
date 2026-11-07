defmodule Vxpipe.Console.MCPListedOAuth do
  @moduledoc "Projects accepted directory recipes into the existing browser OAuth protocol."
  alias Vxpipe.Console.IntegrationsDirectory.Listing

  alias Vxpipe.MCP.{
    OAuthCapabilities,
    OAuthRegistration,
    Preflight,
    ResourceMetadata,
    StaticConfiguration
  }

  @fields ~w(endpoint auth_method revision issuer credentials initial_access_token)
  @client_fields ~w(client_id client_auth_method client_secret private_key algorithm key_id)

  def input(options, tenant, %{"listing" => reference} = input, origin) do
    with :ok <- validate(input, ["listing" | @fields]),
         :ok <- issuer(input),
         {:ok, entry} <- Listing.resolve(reference, Keyword.get(options, :listing_options, [])),
         {:ok, projected} <- project(options, tenant, input, origin, entry),
         do: {:ok, projected, entry}
  end

  def input(_options, _tenant, input, _origin), do: {:ok, input, nil}

  def saved(options, tenant, input, origin, entry) do
    with :ok <- validate(input, @fields),
         :ok <- issuer(input),
         {:ok, projected} <- project(options, tenant, input, origin, entry),
         do: {:ok, projected, entry}
  end

  defp validate(%{"revision" => revision} = input, allowed)
       when is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- allowed == [] and is_map(Map.get(input, "credentials", %{})) and
         String.valid?(revision) and byte_size(JSON.encode!(input)) <= 81_920,
       do: :ok,
       else: {:error, :invalid_oauth_preparation}
  rescue
    _ -> {:error, :invalid_oauth_preparation}
  end

  defp validate(_, _), do: {:error, :invalid_oauth_preparation}

  defp issuer(%{"issuer" => issuer}) do
    with {:ok, _} <- StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil}} <- URI.new(issuer),
         do: :ok,
         else: (_ -> {:error, :invalid_oauth_issuer})
  end

  defp issuer(_), do: :ok

  defp project(options, tenant, input, origin, %{
         "endpoint" => endpoint,
         "authentication" => %{"type" => "oauth2", "registration" => preference}
       })
       when preference in ~w(discover cimd dcr preregistered) do
    discovery_input = input |> Map.take(~w(revision issuer)) |> Map.put("endpoint", endpoint)

    with {:ok, discovery} <- Preflight.discover(tenant, discovery_input, options),
         :ok <- browser_capabilities(discovery),
         method = method(preference, discovery, input, origin, options),
         {:ok, fields} <- fields(method, input) do
      {:ok, discovery_input |> Map.put("auth_method", method) |> Map.merge(fields)}
    end
  end

  defp project(_, _, _, _, _), do: {:error, :invalid_oauth_preparation}

  defp browser_capabilities(%{outcome: :oauth, supported_grants: grants}) do
    if "authorization_code" in grants, do: :ok, else: {:error, :unsupported_oauth_capabilities}
  end

  defp browser_capabilities(%{outcome: :issuer_required}), do: {:error, :oauth_issuer_required}
  defp browser_capabilities(_), do: {:error, :unsupported_oauth_capabilities}

  defp method("preregistered", _, _, _, _), do: "own_client"

  defp method(preference, discovery, input, origin, options) do
    metadata = discovery.oauth
    registration = Keyword.get(options, :registration)
    resource = Map.get(discovery, :resource, %{})

    reusable? =
      not Map.has_key?(input, "initial_access_token") and
        match?(
          {:ok, _},
          OAuthRegistration.reuse(
            registration,
            metadata,
            origin,
            resource["resource"],
            ResourceMetadata.authorization_scopes(resource)
          )
        )

    cond do
      not Map.has_key?(discovery, :resource) -> "own_client"
      reusable? -> "dcr"
      preference == "dcr" and OAuthCapabilities.dcr_supported?(metadata) -> "dcr"
      OAuthCapabilities.cimd_supported?(metadata) -> "cimd"
      OAuthCapabilities.dcr_supported?(metadata) -> "dcr"
      true -> "own_client"
    end
  end

  defp fields("own_client", input) do
    values = Map.get(input, "credentials", %{})

    if Map.keys(values) -- @client_fields == [] and
         not Map.has_key?(input, "initial_access_token"),
       do: {:ok, %{"credentials" => Map.put(values, "grant_type", "authorization_code")}},
       else: {:error, :invalid_oauth_preparation}
  end

  defp fields(method, input) do
    if Map.get(input, "credentials", %{}) == %{} and
         (method == "dcr" or not Map.has_key?(input, "initial_access_token")),
       do: {:ok, Map.take(input, ~w(initial_access_token))},
       else: {:error, :invalid_oauth_preparation}
  end
end
