defmodule Vxpipe.Console.MCPConnectionsController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.MCPConnections
  alias Vxpipe.Console.UserSession

  def preflight(conn, %{"tenant_key" => tenant} = params) do
    case MCPConnections.preflight(
           conn.assigns.user_principal,
           tenant,
           Map.delete(params, "tenant_key"),
           options(conn)
         ) do
      {:ok, result} ->
        json(conn, %{discovery: Map.put_new_lazy(result, :oauth_client, &oauth_client/0)})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def show(conn, %{"tenant_key" => tenant, "id" => id, "retained_generation" => value} = params) do
    with {:ok, generation} <- retained_generation(value),
         true <- Map.keys(params) -- ~w(tenant_key id retained_generation) == [],
         {:ok, record} <-
           MCPConnections.get_retained(
             conn.assigns.user_principal,
             tenant,
             id,
             generation,
             options(conn)
           ) do
      json(conn, %{connection: record})
    else
      {:error, reason} -> error(conn, reason)
      _ -> error(conn, :invalid_mcp_connection)
    end
  end

  def show(conn, %{"tenant_key" => tenant, "id" => id}) do
    case MCPConnections.get(conn.assigns.user_principal, tenant, id) do
      {:ok, record} -> json(conn, %{connection: record})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp retained_generation(value) when is_binary(value) and byte_size(value) in 1..16 do
    with true <- Regex.match?(~r/\A[1-9][0-9]*\z/, value),
         {generation, ""} when generation <= 9_007_199_254_740_991 <- Integer.parse(value),
         do: {:ok, generation},
         else: (_ -> {:error, :invalid_mcp_connection})
  end

  defp retained_generation(_), do: {:error, :invalid_mcp_connection}

  def index(conn, %{"tenant_key" => tenant}) do
    case MCPConnections.list(conn.assigns.user_principal, tenant) do
      {:ok, records} -> json(conn, %{connections: records})
      {:error, reason} -> error(conn, reason)
    end
  end

  def create(conn, %{"tenant_key" => tenant} = params) do
    case MCPConnections.connect(
           conn.assigns.user_principal,
           tenant,
           Map.delete(params, "tenant_key"),
           options(conn)
         ) do
      {:ok, record} -> conn |> put_status(201) |> json(%{connection: record})
      {:error, reason} -> error(conn, reason)
    end
  end

  def update(conn, %{"tenant_key" => tenant, "id" => id, "refresh_tools" => true} = params) do
    if Map.keys(params) -- ~w(tenant_key id generation refresh_tools) == [] do
      case MCPConnections.refresh_tools(
             conn.assigns.user_principal,
             tenant,
             id,
             params["generation"],
             options(conn)
           ) do
        {:ok, record} -> json(conn, %{connection: record})
        {:error, reason} -> error(conn, reason)
      end
    else
      error(conn, :invalid_mcp_configuration)
    end
  end

  def update(conn, %{"tenant_key" => tenant, "id" => id} = params) do
    generation = Map.get(params, "generation")
    input = Map.drop(params, ["tenant_key", "id", "generation"])

    case MCPConnections.update(
           conn.assigns.user_principal,
           tenant,
           id,
           generation,
           input,
           options(conn)
         ) do
      {:ok, record} -> json(conn, %{connection: record})
      {:error, reason} -> error(conn, reason)
    end
  end

  def delete(conn, %{"tenant_key" => tenant, "id" => id} = params) do
    case MCPConnections.disconnect(
           conn.assigns.user_principal,
           tenant,
           id,
           Map.get(params, "generation"),
           options(conn)
         ) do
      {:ok, record} -> json(conn, %{connection: record})
      {:error, reason} -> error(conn, reason)
    end
  end

  def reconnect(conn, %{"tenant_key" => tenant, "id" => id} = params) do
    case MCPConnections.reconnect(
           conn.assigns.user_principal,
           tenant,
           id,
           params["generation"],
           Map.drop(params, ~w(tenant_key id generation)),
           options(conn)
         ) do
      {:ok, record} -> json(conn, %{connection: record})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp options(conn) do
    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    [
      refresh_authority: fn -> UserSession.fetch(conn, backend: backend) end,
      installation_identity: fn -> backend.mcp_oauth_installation() end
    ]
  end

  defp oauth_client do
    backend =
      Application.get_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    with {:ok, %{origin: origin}} <- backend.mcp_oauth_installation(),
         {:ok, document} <- Vxpipe.MCP.ClientMetadata.document(origin),
         [callback] <- document.redirect_uris,
         do: %{callback_url: callback, client_id: document.client_id},
         else: (_ -> nil)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp error(conn, {:mcp_reconnect_required, %{id: id, generation: generation}}),
    do:
      conn
      |> put_status(409)
      |> json(%{
        error: %{code: :mcp_reconnect_required, connection_id: id, generation: generation}
      })

  defp error(conn, {:mcp_connection_exists, id}) when is_binary(id),
    do:
      conn
      |> put_status(409)
      |> json(%{error: %{code: :mcp_connection_exists, connection_id: id}})

  defp error(conn, reason) do
    {status, code} =
      case reason do
        :forbidden ->
          {403, reason}

        reason when reason in [:not_found, :tenant_not_found, :mcp_connection_not_found] ->
          {404, :mcp_connection_not_found}

        reason
        when reason in [
               :stale_mcp_connection,
               :mcp_installation_changed,
               :mcp_connection_revoked,
               :mcp_reconnect_not_required
             ] ->
          {409, reason}

        :oauth_reconnect_required ->
          {409, reason}

        reason
        when reason in [
               :invalid_tenant_key,
               :invalid_mcp_connection,
               :invalid_mcp_configuration,
               :invalid_mcp_endpoint,
               :invalid_mcp_preflight,
               :invalid_mcp_listing,
               :invalid_oauth_issuer,
               :invalid_own_oauth_configuration,
               :oauth_issuer_required,
               :oauth_machine_grant_required,
               :invalid_mcp_authentication
             ] ->
          {422, reason}

        reason when reason in [:mcp_connection_busy, :oauth_refresh_in_progress] ->
          {429, reason}

        :mcp_listing_unavailable ->
          {503, reason}

        _unavailable ->
          {503, :mcp_connection_unavailable}
      end

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end
