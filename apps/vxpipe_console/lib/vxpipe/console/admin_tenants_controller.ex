defmodule Vxpipe.Console.AdminTenantsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Console.AdminPageParameter

  def create(conn, params) do
    case Vxpipe.Calls.TenantCreation.create(conn.assigns.user_principal, Map.get(params, "name")) do
      {:ok, tenant} ->
        conn |> put_status(201) |> json(%{tenant: tenant_json(tenant)})

      {:error, :forbidden} ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :invalid_tenant_name} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_tenant_name"}})

      {:error, _} ->
        conn |> put_status(503) |> json(%{error: %{code: "tenant_creation_unavailable"}})
    end
  end

  def index(conn, params) do
    with {:ok, page} <- AdminPageParameter.parse(params),
         {:ok, page_size} <- page_size(params),
         {:ok, tenant_page} <-
           Vxpipe.Calls.search_operator_tenants(conn.assigns.user_principal,
             page: page,
             limit: page_size,
             query: Map.get(params, "q", "")
           ) do
      json(conn, %{
        tenants: Enum.map(tenant_page.tenants, &tenant_json/1),
        pagination: %{
          page: tenant_page.page,
          page_size: tenant_page.page_size,
          total: tenant_page.total,
          total_pages: tenant_page.total_pages,
          has_next: tenant_page.page < tenant_page.total_pages
        }
      })
    else
      {:error, reason} when reason in [:invalid_page, :tenant_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, :forbidden} ->
        conn |> put_status(403) |> json(%{error: %{code: "forbidden"}})

      {:error, :invalid_tenant_page_request} ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_query"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "tenant_directory_unavailable"}})
    end
  end

  defp tenant_json(tenant) do
    %{
      key: tenant.key,
      name: tenant.name,
      dashboard_path: Vxpipe.Console.NavigationProjection.dashboard_path(tenant.key),
      created_at: DateTime.to_iso8601(tenant.inserted_at)
    }
  end

  defp page_size(params) do
    with {:ok, size} <- AdminPageParameter.parse(%{"page" => Map.get(params, "page_size", "25")}),
         true <- size <= 50 do
      {:ok, size}
    else
      _ -> {:error, :invalid_tenant_page_request}
    end
  end
end
