defmodule Vxpipe.MCP.Preflight do
  @moduledoc "Credentialless discovery composition. Never saves, registers, exchanges tokens or invokes tools."
  alias Vxpipe.MCP.{
    ConnectionCheck,
    OAuthCapabilities,
    OAuthMetadata,
    ResourceMetadata,
    StaticConfiguration
  }

  def discover(tenant, input, options \\ []) do
    options = Vxpipe.MCP.DiscoveryIO.options(options)

    with :ok <- validate(input),
         {:ok, _endpoint} <- StaticConfiguration.endpoint(input["endpoint"]) do
      context = %{endpoint: input["endpoint"], revision: input["revision"], suggested_method: nil}

      case ResourceMetadata.discover(input["endpoint"], options) do
        {:ok, resource} ->
          oauth(context, resource, input["issuer"], options)

        {:error, :resource_metadata_missing} ->
          missing_resource(tenant, context, input["issuer"], options)

        {:error, reason} ->
          {:ok, Map.merge(context, %{outcome: :unknown, reason: reason})}
      end
    end
  end

  defp validate(%{"endpoint" => endpoint, "revision" => revision} = input)
       when is_binary(endpoint) and is_binary(revision) and byte_size(revision) in 1..128 do
    if Map.keys(input) -- ~w(endpoint revision issuer) == [] and String.valid?(revision) and
         (not Map.has_key?(input, "issuer") or valid_issuer?(input["issuer"])),
       do: :ok,
       else: {:error, :invalid_mcp_preflight}
  end

  defp validate(_input), do: {:error, :invalid_mcp_preflight}

  defp valid_issuer?(issuer) do
    with {:ok, _} <- StaticConfiguration.endpoint(issuer),
         {:ok, %URI{query: nil}} <- URI.new(issuer),
         do: true,
         else: (_ -> false)
  end

  defp missing_resource(tenant, context, nil, options), do: anonymous(tenant, context, options)

  defp missing_resource(_tenant, context, issuer, options) do
    context = Map.put(context, :issuers, [issuer])

    with {:ok, result} <- issuer_metadata(context, issuer, options) do
      {:ok,
       if(result.outcome == :oauth, do: %{result | suggested_method: "own_client"}, else: result)}
    end
  end

  defp oauth(context, resource, selected, options) do
    issuers = resource["authorization_servers"]
    context = Map.merge(context, %{resource: resource, issuers: issuers})

    case select_issuer(issuers, selected) do
      {:ok, issuer} -> issuer_metadata(context, issuer, options)
      :choice -> {:ok, Map.put(context, :outcome, :issuer_required)}
      {:error, _reason} = error -> error
    end
  end

  defp select_issuer([issuer], nil), do: {:ok, issuer}
  defp select_issuer(_issuers, nil), do: :choice

  defp select_issuer(issuers, selected) do
    if selected in issuers, do: {:ok, selected}, else: {:error, :invalid_oauth_issuer}
  end

  defp issuer_metadata(context, issuer, options) do
    case OAuthMetadata.discover(issuer, options) do
      {:ok, metadata} ->
        grants = OAuthCapabilities.supported_grants(metadata)

        case grants do
          [_ | _] ->
            {:ok,
             Map.merge(context, %{
               outcome: :oauth,
               oauth: metadata,
               supported_grants: grants,
               suggested_method:
                 if("authorization_code" in grants,
                   do: suggested_method(metadata),
                   else: "own_client"
                 )
             })}

          [] ->
            {:ok,
             Map.merge(context, %{
               outcome: :unsupported_oauth,
               oauth: metadata,
               supported_grants: [],
               reason: :unsupported_oauth_capabilities
             })}
        end

      {:error, reason} ->
        {:ok, Map.merge(context, %{outcome: :partial, issuer: issuer, reason: reason})}
    end
  end

  defp suggested_method(%{"client_id_metadata_document_supported" => true}), do: "cimd"

  defp suggested_method(%{"registration_endpoint" => endpoint}) when is_binary(endpoint),
    do: "dcr"

  defp suggested_method(_metadata), do: "own_client"

  defp anonymous(tenant, context, options) do
    {:ok, configuration} =
      StaticConfiguration.new(%{
        "endpoint" => context.endpoint,
        "auth_method" => "none",
        "credentials" => %{}
      })

    check = Keyword.get(options, :anonymous_check, &ConnectionCheck.run/2)

    case check.(tenant, configuration) do
      {:ok, %{server_name: name}} ->
        {:ok,
         Map.merge(context, %{outcome: :anonymous, suggested_method: "none", server_name: name})}

      _failed ->
        {:ok, Map.merge(context, %{outcome: :unknown, reason: :mcp_connection_failed})}
    end
  end
end
