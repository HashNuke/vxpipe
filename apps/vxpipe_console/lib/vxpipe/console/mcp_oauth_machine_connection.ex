defmodule Vxpipe.Console.MCPOAuthMachineConnection do
  @moduledoc "Bounded registered-client token acquisition and MCP validation without browser consent."
  alias Vxpipe.Calls.ResolvedMCPConnection

  alias Vxpipe.MCP.{
    ConnectionCheck,
    OAuthTokenExchange,
    OwnOAuthPreparation,
    PreflightRunner,
    StaticConfiguration
  }

  @metadata ~w(issuer token_endpoint grant_types_supported token_endpoint_auth_methods_supported
    token_endpoint_auth_signing_alg_values_supported)

  def check(options, tenant, input) do
    runner = Keyword.get(options, :preflight_runner, PreflightRunner)
    PreflightRunner.run(runner, tenant, fn -> connect(options, tenant, input) end)
  catch
    :exit, _ -> {:error, :mcp_connection_failed}
  end

  defp connect(
         options,
         tenant,
         %{"credentials" => %{"grant_type" => "client_credentials"}} = input
       ) do
    check = Keyword.get(options, :connection_check, &ConnectionCheck.run/2)

    with {:ok, configured} <- OwnOAuthPreparation.configuration(input, nil, options),
         requested_at = Keyword.get(options, :now, &DateTime.utc_now/0).(),
         {:ok, token} <-
           OAuthTokenExchange.client_credentials(
             configured.token_request,
             configured.metadata,
             options
           ),
         {:ok, configuration} <-
           StaticConfiguration.new(%{
             "endpoint" => configured.endpoint,
             "auth_method" => "bearer",
             "credentials" => %{
               "token" => token.access_token,
               "headers" => configured.secrets["headers"]
             }
           }),
         {:ok, %{server_name: name, catalog: catalog}} when is_binary(name) and is_list(catalog) <-
           check.(tenant, configuration) do
      expires =
        if token.expires_in,
          do: requested_at |> DateTime.add(token.expires_in) |> DateTime.to_iso8601()

      {:ok,
       %ResolvedMCPConnection{
         connection: %{
           endpoint: configured.endpoint,
           endpoint_identity: configuration.endpoint,
           auth_method: "oauth",
           server_name: name,
           catalog: catalog,
           directory_id: nil
         },
         secrets:
           Map.merge(configured.secrets, %{
             "machine_metadata" => Map.take(configured.metadata, @metadata),
             "access_token" => token.access_token,
             "expires_at" => expires,
             "scope" => token.scope
           })
       }}
    else
      {:error, reason}
      when reason in [
             :invalid_own_oauth_configuration,
             :invalid_mcp_endpoint,
             :invalid_oauth_issuer,
             :oauth_issuer_required,
             :mcp_connection_busy
           ] ->
        {:error, reason}

      _ ->
        {:error, :mcp_connection_failed}
    end
  end

  defp connect(_, _, _), do: {:error, :oauth_machine_grant_required}
end
