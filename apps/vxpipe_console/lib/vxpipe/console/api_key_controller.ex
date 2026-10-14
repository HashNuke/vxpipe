defmodule Vxpipe.Console.ApiKeyController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  alias Vxpipe.Calls.{ApiKeyAccess, ApiKeyManagement}

  def index(conn, params) do
    principal = conn.assigns.user_principal

    case ApiKeyManagement.list(principal, params) do
      {:ok, page} ->
        keys = Enum.map(page.keys, &present(&1, principal))

        kinds =
          Enum.filter(["calls", "full", "platform"], fn
            "platform" -> ApiKeyAccess.platform_write?(principal)
            "calls" -> ApiKeyAccess.scope(principal, :calls) != {:keys, []}
            "full" -> ApiKeyAccess.scope(principal, :full) != {:keys, []}
          end)

        json(conn, %{keys: keys, pagination: pagination(page), creatable_kinds: kinds})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def tenants(conn, params) do
    kind = Map.get(params, "kind")

    if kind in ["calls", "full"] do
      case ApiKeyManagement.tenants(conn.assigns.user_principal, kind, params) do
        {:ok, page} -> json(conn, %{tenants: page.tenants, pagination: pagination(page)})
        {:error, reason} -> error(conn, reason)
      end
    else
      error(conn, :invalid_key_type)
    end
  end

  def create(conn, params) do
    principal = conn.assigns.user_principal

    case ApiKeyManagement.create(
           principal,
           Map.get(params, "name"),
           Map.get(params, "kind"),
           Map.get(params, "tenant_key")
         ) do
      {:ok, issued} ->
        conn
        |> put_status(201)
        |> json(%{key: present(issued.key, principal), secret: issued.secret})

      {:error, reason} ->
        error(conn, reason)
    end
  end

  def delete(conn, %{"id" => id}) do
    case ApiKeyManagement.revoke(conn.assigns.user_principal, id) do
      :ok -> send_resp(conn, 204, "")
      {:error, reason} -> error(conn, reason)
    end
  end

  defp present(key, principal) do
    tenant = if key.tenant, do: key.tenant.key

    key
    |> Map.put(:created_at, DateTime.to_iso8601(key.created_at))
    |> Map.put(:can_revoke, ApiKeyAccess.authorize_write(principal, tenant) == :ok)
  end

  defp pagination(page),
    do: %{
      page: page.page,
      page_size: page.page_size,
      total: page.total,
      has_next: page.page * page.page_size < page.total
    }

  defp error(conn, reason) do
    status =
      case reason do
        :forbidden -> 403
        value when value in [:not_found, :tenant_not_found] -> 404
        value when value in [:invalid_name, :invalid_query, :invalid_key_type] -> 422
        _ -> 503
      end

    code = if status == 503, do: :api_keys_unavailable, else: reason
    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end
