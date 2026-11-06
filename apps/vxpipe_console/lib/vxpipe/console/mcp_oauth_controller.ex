defmodule Vxpipe.Console.MCPOAuthController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  def create(conn, %{"tenant_key" => tenant} = params) do
    result =
      with {:ok, input, options} <- request_context(conn, tenant, params) do
        Vxpipe.Calls.MCPOAuthAttempts.start(conn.assigns.user_principal, tenant, input, options)
      end

    handoff(conn, result)
  end

  def reconnect(conn, %{"tenant_key" => tenant, "id" => id} = params) do
    result =
      with {:ok, input, options} <- request_context(conn, tenant, params) do
        Vxpipe.Calls.MCPOAuthAttempts.reconnect(
          conn.assigns.user_principal,
          tenant,
          id,
          input,
          options
        )
      end

    handoff(conn, result)
  end

  defp request_context(conn, tenant, params) do
    with {:ok, location} <-
           Vxpipe.Console.MCPOAuthReturnLocation.validate(tenant, params["return_to"]) do
      {:ok, Map.drop(params, ["tenant_key", "id", "return_to"]),
       Keyword.put(options(conn), :oauth_return_to, location)}
    end
  end

  defp handoff(conn, result) do
    case result do
      {:ok, handoff} ->
        conn |> put_status(201) |> json(handoff)

      {:error, :forbidden} ->
        failure(conn, 403, :forbidden)

      {:error, reason} when reason in [:mcp_installation_changed, :stale_mcp_connection] ->
        failure(conn, 409, reason)

      {:error, reason} when reason in [:mcp_connection_not_found, :mcp_connection_revoked] ->
        failure(conn, 404, :mcp_connection_not_found)

      {:error, reason}
      when reason in [
             :invalid_oauth_preparation,
             :invalid_own_oauth_configuration,
             :oauth_browser_grant_required,
             :invalid_oauth_reconnect,
             :invalid_oauth_return_location,
             :invalid_mcp_endpoint,
             :invalid_oauth_issuer,
             :oauth_issuer_required,
             :unsupported_oauth_capabilities,
             :oauth_registration_unavailable
           ] ->
        failure(conn, 422, reason)

      {:error, reason} when reason in [:oauth_attempt_busy, :mcp_connection_busy] ->
        failure(conn, 429, reason)

      _ ->
        failure(conn, 503, :oauth_connection_unavailable)
    end
  end

  def callback(conn, _params) do
    conn = Plug.Conn.put_resp_header(conn, "referrer-policy", "no-referrer")

    with {:ok, callback} <- Vxpipe.MCP.OAuthCallback.parse(conn.query_string),
         {:ok, tenant, connection} <-
           Vxpipe.Calls.MCPOAuthAttempts.complete(
             conn.assigns.user_principal,
             callback.state,
             callback,
             options(conn)
           ) do
      conn
      |> put_status(303)
      |> redirect(
        to:
          Vxpipe.Console.MCPOAuthReturnLocation.connected(
            tenant,
            Map.get(connection, :return_to),
            Map.get(connection, :attempt_id)
          )
      )
    else
      {:error, reason, %{tenant_key: tenant, return_to: return_to, attempt_id: attempt_id}} ->
        conn
        |> put_status(303)
        |> redirect(
          to: Vxpipe.Console.MCPOAuthReturnLocation.failed(tenant, return_to, reason, attempt_id)
        )

      {:error, :forbidden} ->
        failure(conn, 403, :forbidden)

      {:error, reason}
      when reason in [:stale_mcp_connection, :mcp_connection_not_found, :mcp_connection_revoked] ->
        failure(conn, 409, :stale_mcp_connection)

      {:error, reason}
      when reason in [
             :invalid_oauth_callback,
             :oauth_attempt_unavailable,
             :oauth_issuer_mismatch,
             :oauth_consent_denied,
             :oauth_authorization_failed,
             :mcp_installation_changed
           ] ->
        failure(conn, 400, reason)

      _ ->
        failure(conn, 503, :oauth_connection_unavailable)
    end
  end

  defp options(conn) do
    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    [
      refresh_authority: fn -> Vxpipe.Console.UserSession.fetch(conn, backend: backend) end,
      installation_identity: fn -> backend.mcp_oauth_installation() end
    ]
  end

  defp failure(conn, status, code),
    do: conn |> put_status(status) |> json(%{error: %{code: code}})
end
