defmodule Vxpipe.Console.MCPOAuthCompletion do
  @moduledoc "Redeems a claimed OAuth callback and verifies MCP initialization before persistence."
  alias Vxpipe.Calls.{ResolvedMCPOAuthAttempt, ResolvedMCPConnection}
  alias Vxpipe.Console.MCPOAuthTokenRequest
  alias Vxpipe.MCP.{ConnectionCheck, OAuthCallback, OAuthTokenExchange, StaticConfiguration}

  def complete(options, tenant, callback, attempt) do
    runner = Keyword.get(options, :completion_runner, Vxpipe.MCP.OAuthCompletionRunner)

    case Vxpipe.MCP.PreflightRunner.run(runner, tenant, fn ->
           complete_protocol(options, tenant, callback, attempt)
         end) do
      {:error, :mcp_discovery_unavailable} -> {:error, :oauth_completion_failed}
      result -> result
    end
  catch
    :exit, _ -> {:error, :oauth_completion_failed}
  end

  defp complete_protocol(options, tenant, callback, %ResolvedMCPOAuthAttempt{
         attempt: attempt,
         secrets: secrets
       }) do
    with {:ok, code} <-
           OAuthCallback.validate(callback, attempt.issuer, secrets["issuer_response_required"]),
         {:ok, request} <- MCPOAuthTokenRequest.build(secrets, attempt.resource),
         request =
           Map.merge(request, %{
             code: code,
             code_verifier: secrets["code_verifier"],
             redirect_uri: attempt.redirect_uri
           }),
         requested_at = Keyword.get(options, :now, &DateTime.utc_now/0).(),
         {:ok, token} <- OAuthTokenExchange.exchange(request, options),
         {:ok, configuration} <-
           StaticConfiguration.new(%{
             "endpoint" => attempt.resource,
             "auth_method" => "bearer",
             "credentials" => %{
               "token" => token.access_token,
               "headers" => Map.get(secrets, "headers", [])
             }
           }),
         {:ok, discovered} <- check(options, tenant, configuration) do
      {:ok,
       %ResolvedMCPConnection{
         connection: %{
           id: attempt.connection_id,
           generation: attempt.generation,
           endpoint: attempt.resource,
           endpoint_identity: configuration.endpoint,
           directory_id: nil,
           auth_method: "oauth",
           server_name: discovered.server_name,
           catalog: discovered.catalog
         },
         secrets:
           secrets
           |> Map.drop(["code_verifier", "issuer_response_required"])
           |> Map.merge(%{
             "access_token" => token.access_token,
             "refresh_token" => token.refresh_token,
             "expires_at" => expires_at(token.expires_in, requested_at),
             "scope" => token.scope,
             "issuer" => attempt.issuer,
             "resource" => attempt.resource
           })
       }}
    else
      {:error, reason}
      when reason in [
             :oauth_issuer_mismatch,
             :oauth_consent_denied,
             :oauth_authorization_failed,
             :oauth_grant_rejected,
             :oauth_token_exchange_failed,
             :invalid_oauth_token_response,
             :mcp_connection_failed
           ] ->
        {:error, reason}

      _ ->
        {:error, :oauth_completion_failed}
    end
  end

  defp check(options, tenant, configuration) do
    check = Keyword.get(options, :connection_check, &ConnectionCheck.run/2)

    case check.(tenant, configuration) do
      {:ok, %{server_name: name, catalog: catalog} = discovered}
      when is_binary(name) and is_list(catalog) ->
        {:ok, discovered}

      _ ->
        {:error, :mcp_connection_failed}
    end
  end

  defp expires_at(nil, _requested_at), do: nil

  defp expires_at(seconds, requested_at),
    do: requested_at |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
