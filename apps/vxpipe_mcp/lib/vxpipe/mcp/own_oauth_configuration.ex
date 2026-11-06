defmodule Vxpipe.MCP.OwnOAuthConfiguration do
  @moduledoc "Validated registered-client configuration, separate from managed CIMD/DCR registration."
  alias ExMCP.Authorization.EndpointPolicy

  alias Vxpipe.MCP.{
    ClientMetadata,
    OAuthAuthorization,
    OAuthClientAssertion,
    OAuthRequestParameters,
    ResourceMetadata,
    StaticConfiguration
  }

  @derive {Inspect, only: [:grant_type]}
  @enforce_keys [
    :endpoint,
    :grant_type,
    :metadata,
    :authorization_context,
    :token_request,
    :secrets
  ]
  defstruct @enforce_keys
  @fields ~w(grant_type client_id client_auth_method client_secret private_key algorithm key_id
    authorization_endpoint token_endpoint revocation_endpoint scopes resource audience
    authorization_parameters token_parameters headers)
  @methods %{
    "none" => :none,
    "client_secret_basic" => :client_secret_basic,
    "client_secret_post" => :client_secret_post,
    "private_key_jwt" => :private_key_jwt
  }

  def new(
        %{
          "endpoint" => endpoint,
          "auth_method" => "own_client",
          "revision" => revision,
          "credentials" => values
        } = input,
        metadata,
        resource,
        origin
      )
      when is_map(values) and is_map(metadata) and is_map(resource) do
    with true <- Map.keys(input) -- ~w(endpoint auth_method revision credentials issuer) == [],
         true <- Map.keys(values) -- @fields == [],
         true <- text?(revision, 128),
         {:ok, _} <- StaticConfiguration.endpoint(endpoint),
         true <- resource["resource"] == endpoint,
         true <- Map.get(values, "resource", endpoint) == endpoint,
         true <- bound_issuer?(input["issuer"], metadata["issuer"], resource),
         {:ok, grant} <- grant(values, metadata),
         {:ok, configured} <- endpoints(values, metadata, grant),
         {:ok, scopes} <-
           scopes(Map.get(values, "scopes", ResourceMetadata.authorization_scopes(resource))),
         :ok <- request_parameters(values, configured, grant),
         :ok <- headers(endpoint, values),
         {:ok, client, client_secrets} <- client(values, configured),
         {:ok, context, callback} <-
           authorization_context(grant, origin, endpoint, scopes, values) do
      token_request =
        Map.merge(client, %{
          token_endpoint: configured["token_endpoint"],
          resource: endpoint,
          parameters: Map.get(values, "token_parameters", []),
          audience: values["audience"]
        })

      token_request =
        if grant == "client_credentials" and scopes != [],
          do: Map.put(token_request, :scope, Enum.join(scopes, " ")),
          else: token_request

      secrets =
        Map.merge(client_secrets, %{
          "registration_method" => "own_client",
          "grant_type" => grant,
          "issuer" => configured["issuer"],
          "resource" => endpoint,
          "token_endpoint" => configured["token_endpoint"],
          "revocation_endpoint" => configured["revocation_endpoint"],
          "scopes" => scopes,
          "audience" => values["audience"],
          "token_parameters" => Map.get(values, "token_parameters", []),
          "headers" => Map.get(values, "headers", [])
        })

      secrets =
        if callback,
          do:
            Map.merge(secrets, %{
              "redirect_uri" => callback,
              "authorization_endpoint" => configured["authorization_endpoint"],
              "authorization_parameters" => Map.get(values, "authorization_parameters", [])
            }),
          else: secrets

      {:ok,
       %__MODULE__{
         endpoint: endpoint,
         grant_type: grant,
         metadata: configured,
         authorization_context: context,
         token_request: token_request,
         secrets: secrets
       }}
    else
      _ -> {:error, :invalid_own_oauth_configuration}
    end
  rescue
    _ -> {:error, :invalid_own_oauth_configuration}
  end

  def new(_, _, _, _), do: {:error, :invalid_own_oauth_configuration}

  defp bound_issuer?(selected, issuer, resource) do
    with {:ok, _} <- StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil}} <- URI.new(issuer),
         issuers when is_list(issuers) <- resource["authorization_servers"],
         true <- issuer in issuers,
         do: (is_nil(selected) and length(issuers) == 1) or selected == issuer,
         else: (_ -> false)
  end

  defp grant(values, metadata) do
    grant = values["grant_type"]
    grants = Map.get(metadata, "grant_types_supported", ["authorization_code"])

    with true <- grant in ["authorization_code", "client_credentials"],
         true <- is_list(grants) and grant in grants,
         :ok <- grant_capabilities(grant, values, metadata),
         do: {:ok, grant}
  end

  defp grant_capabilities("authorization_code", _values, metadata),
    do: OAuthAuthorization.validate_capabilities(metadata)

  defp grant_capabilities("client_credentials", values, _metadata) do
    if values["client_auth_method"] != "none" and
         not Map.has_key?(values, "authorization_endpoint") and
         not Map.has_key?(values, "authorization_parameters"), do: :ok, else: :invalid
  end

  defp endpoints(values, metadata, grant) do
    metadata =
      Map.merge(
        metadata,
        Map.take(values, ~w(authorization_endpoint token_endpoint revocation_endpoint))
      )

    required =
      if grant == "authorization_code",
        do: ~w(authorization_endpoint token_endpoint),
        else: ~w(token_endpoint)

    endpoints =
      Enum.map(required, &metadata[&1]) ++
        if(Map.has_key?(metadata, "revocation_endpoint"),
          do: [metadata["revocation_endpoint"]],
          else: []
        )

    with :ok <-
           EndpointPolicy.validate_metadata(metadata, metadata["issuer"],
             allow_insecure_loopback: false
           ),
         true <- Enum.all?(endpoints, &valid_endpoint?/1),
         do: {:ok, metadata}
  end

  defp valid_endpoint?(endpoint) do
    with {:ok, _} <- StaticConfiguration.endpoint(endpoint),
         {:ok, _} <- OAuthRequestParameters.endpoint_query(endpoint),
         do: true,
         else: (_ -> false)
  end

  defp request_parameters(values, metadata, grant) do
    paths =
      if grant == "authorization_code",
        do: [
          {"authorization_parameters", "authorization_endpoint"},
          {"token_parameters", "token_endpoint"}
        ],
        else: [{"token_parameters", "token_endpoint"}]

    Enum.reduce_while(paths, :ok, fn {field, endpoint}, :ok ->
      with {:ok, parameters} <-
             OAuthRequestParameters.validate(Map.get(values, field, []), values["audience"]),
           {:ok, query} <- OAuthRequestParameters.endpoint_query(metadata[endpoint]),
           false <- Enum.any?(Map.keys(parameters), &Map.has_key?(query, &1)) do
        {:cont, :ok}
      else
        _ -> {:halt, :invalid}
      end
    end)
  end

  defp scopes(values) when is_list(values) and length(values) <= 64 do
    if Enum.all?(values, fn scope ->
         is_binary(scope) and byte_size(scope) in 1..256 and
           Enum.all?(:binary.bin_to_list(scope), &(&1 == 33 or &1 in 35..91 or &1 in 93..126))
       end), do: {:ok, Enum.uniq(values)}, else: :invalid
  end

  defp scopes(_), do: :invalid

  defp headers(endpoint, values) do
    case StaticConfiguration.new(%{
           "endpoint" => endpoint,
           "auth_method" => "bearer",
           "credentials" => %{
             "token" => "validation-placeholder",
             "headers" => Map.get(values, "headers", [])
           }
         }) do
      {:ok, _} -> :ok
      _ -> :invalid
    end
  end

  defp client(values, metadata) do
    methods = Map.get(metadata, "token_endpoint_auth_methods_supported", ["client_secret_basic"])

    with true <- text?(values["client_id"], 2048),
         true <- is_list(methods) and values["client_auth_method"] in methods,
         {:ok, method} <- Map.fetch(@methods, values["client_auth_method"]),
         {:ok, authentication, secrets} <- credentials(method, values, metadata) do
      {:ok, Map.merge(authentication, %{client_id: values["client_id"], auth_method: method}),
       Map.merge(secrets, %{
         "client_id" => values["client_id"],
         "auth_method" => values["client_auth_method"]
       })}
    end
  end

  defp credentials(:none, values, _metadata) do
    if Map.take(values, ~w(client_secret private_key algorithm key_id)) == %{},
      do: {:ok, %{}, %{}},
      else: :invalid
  end

  defp credentials(method, values, _metadata)
       when method in [:client_secret_basic, :client_secret_post] do
    if text?(values["client_secret"], 8192) and
         Map.take(values, ~w(private_key algorithm key_id)) == %{},
       do:
         {:ok, %{client_secret: values["client_secret"]},
          %{"client_secret" => values["client_secret"]}},
       else: :invalid
  end

  defp credentials(:private_key_jwt, values, metadata) do
    input = %{
      client_id: values["client_id"],
      token_endpoint: metadata["token_endpoint"],
      private_key: values["private_key"],
      algorithm: values["algorithm"],
      key_id: values["key_id"]
    }

    with false <- Map.has_key?(values, "client_secret"),
         {:ok, signing} <- OAuthClientAssertion.new(input, metadata) do
      secrets =
        values
        |> Map.take(~w(private_key algorithm key_id))
        |> Map.put(
          "signing_algorithms",
          metadata["token_endpoint_auth_signing_alg_values_supported"]
        )

      {:ok, %{client_assertion: signing}, secrets}
    end
  end

  defp authorization_context("client_credentials", _origin, _endpoint, _scopes, _values),
    do: {:ok, nil, nil}

  defp authorization_context("authorization_code", origin, endpoint, scopes, values) do
    with {:ok, document} <- ClientMetadata.document(origin),
         {:ok, _} <-
           OAuthRequestParameters.validate(
             Map.get(values, "authorization_parameters", []),
             values["audience"]
           ) do
      [callback] = document.redirect_uris

      {:ok,
       %{
         origin: origin,
         resource: endpoint,
         scopes: scopes,
         audience: values["audience"],
         parameters: Map.get(values, "authorization_parameters", [])
       }, callback}
    end
  end

  defp text?(value, max),
    do:
      is_binary(value) and byte_size(value) in 1..max and String.valid?(value) and
        not Regex.match?(~r/[\x00-\x1f\x7f]/, value)
end
