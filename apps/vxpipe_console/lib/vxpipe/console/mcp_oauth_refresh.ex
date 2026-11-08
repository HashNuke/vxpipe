defmodule Vxpipe.Console.MCPOAuthRefresh do
  @moduledoc "Projects a private durable renewal claim into the saved OAuth grant's token request."
  alias Vxpipe.Console.MCPOAuthTokenRequest

  def run(options, tenant, operation) do
    runner = Keyword.get(options, :renewal_runner, Vxpipe.MCP.OAuthRenewalRunner)

    case Keyword.fetch(options, :mcp_session) do
      {:ok, integration} ->
        Vxpipe.MCP.PreflightRunner.run_owned(runner, tenant, integration, operation)

      :error ->
        Vxpipe.MCP.PreflightRunner.run(runner, tenant, operation)
    end
  catch
    :exit, _ -> {:error, :oauth_reconnect_required}
  end

  def run_owned(options, tenant, operation, session),
    do: run(Keyword.put(options, :mcp_session, session), tenant, operation)

  def refresh_owned(options, claim, session),
    do: refresh(Keyword.put(options, :mcp_session, session), claim)

  def refresh(options, %Vxpipe.Calls.ResolvedMCPRefresh{secrets: secrets}) do
    requested_at = Keyword.get(options, :now, &DateTime.utc_now/0).()

    with {:ok, token} <- exchange(secrets, options) do
      expires =
        if token.expires_in,
          do: requested_at |> DateTime.add(token.expires_in) |> DateTime.to_iso8601()

      tokens = %{"access_token" => token.access_token, "expires_at" => expires}

      tokens =
        if token.refresh_token,
          do: Map.put(tokens, "refresh_token", token.refresh_token),
          else: tokens

      tokens = if token.scope, do: Map.put(tokens, "scope", token.scope), else: tokens
      {:ok, tokens}
    end
  end

  defp exchange(%{"grant_type" => "client_credentials"} = secrets, options) do
    with {:ok, request, metadata} <- MCPOAuthTokenRequest.machine(secrets),
         do: Vxpipe.MCP.OAuthTokenExchange.client_credentials(request, metadata, options)
  end

  defp exchange(%{"grant_type" => grant}, _) when grant != "authorization_code",
    do: {:error, :oauth_reconnect_required}

  defp exchange(secrets, options) do
    with {:ok, request} <- MCPOAuthTokenRequest.build(secrets, secrets["resource"]),
         do:
           Vxpipe.MCP.OAuthTokenExchange.refresh(
             Map.put(request, :refresh_token, secrets["refresh_token"]),
             options
           )
  end
end
