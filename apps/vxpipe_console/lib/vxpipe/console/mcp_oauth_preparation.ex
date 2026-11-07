defmodule Vxpipe.Console.MCPOAuthPreparation do
  @moduledoc "Runs bounded protocol preparation and projects its private result for Calls persistence."

  def prepare_reconnect(options, tenant, input, origin, registration) do
    prepare(Keyword.put(options, :registration, registration), tenant, input, origin)
  end

  def prepare(options, tenant, input, origin) do
    run(options, tenant, fn ->
      with {:ok, input, entry} <-
             Vxpipe.Console.MCPListedOAuth.input(options, tenant, input, origin),
           do: prepare_protocol(options, input, origin, entry)
    end)
  end

  def prepare_saved(options, tenant, input, origin, registration, entry) do
    options = Keyword.put(options, :registration, registration)

    run(options, tenant, fn ->
      with {:ok, input, entry} <-
             Vxpipe.Console.MCPListedOAuth.saved(options, tenant, input, origin, entry),
           do: prepare_protocol(options, input, origin, entry)
    end)
  end

  defp run(options, tenant, operation) do
    runner = Keyword.get(options, :preflight_runner, Vxpipe.MCP.PreflightRunner)
    Vxpipe.MCP.PreflightRunner.run(runner, tenant, operation)
  catch
    :exit, _ -> {:error, :oauth_preparation_failed}
  end

  defp prepare_protocol(options, input, origin, entry) do
    with {:ok, prepared} <- Vxpipe.MCP.OAuthPreparation.prepare(input, origin, options) do
      authorization = prepared.authorization

      {:ok,
       %Vxpipe.Calls.PreparedMCPOAuth{
         authorization_url: authorization.authorization_url,
         attributes: %{
           state: authorization.state,
           issuer: authorization.issuer,
           redirect_uri: authorization.redirect_uri,
           resource: authorization.resource,
           draft_revision: prepared.draft_revision
         },
         secrets:
           %{
             "code_verifier" => authorization.code_verifier,
             "registration_method" => input["auth_method"],
             "redirect_uri" => authorization.redirect_uri,
             "client_id" => prepared.client.client_id,
             "client_secret" => prepared.client.client_secret,
             "client_secret_expires_at" => prepared.client.client_secret_expires_at,
             "auth_method" => Atom.to_string(prepared.client.auth_method),
             "token_endpoint" => prepared.token_endpoint,
             "scopes" => authorization.scopes,
             "issuer_response_required" => prepared.issuer_response_required
           }
           |> Map.merge(prepared.extra_secrets || %{})
           |> listing(entry)
       }}
    end
  end

  defp listing(secrets, nil), do: secrets
  defp listing(secrets, entry), do: Map.put(secrets, "directory_entry", entry)
end
