defmodule Vxpipe.Console.MCPOAuthPreparation do
  @moduledoc "Runs bounded protocol preparation and projects its private result for Calls persistence."

  def prepare_reconnect(options, tenant, input, origin, registration) do
    prepare(Keyword.put(options, :registration, registration), tenant, input, origin)
  end

  def prepare(options, tenant, input, origin) do
    runner = Keyword.get(options, :preflight_runner, Vxpipe.MCP.PreflightRunner)

    Vxpipe.MCP.PreflightRunner.run(runner, tenant, fn ->
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
         }}
      end
    end)
  catch
    :exit, _ -> {:error, :oauth_preparation_failed}
  end
end
