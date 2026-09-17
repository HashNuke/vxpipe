defmodule Vxpipe.Console.AdminTenantsController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls.InstallationOperator

  def index(conn, params) do
    with {:ok, page} <- page_number(params),
         {:ok, tenant_page} <-
           Vxpipe.Calls.list_operator_tenants(InstallationOperator.authority(), page: page) do
      json(conn, %{
        tenants: Enum.map(tenant_page.tenants, &tenant_json/1),
        pagination: %{
          page: tenant_page.page,
          page_size: tenant_page.page_size,
          total: tenant_page.total,
          total_pages: tenant_page.total_pages
        }
      })
    else
      {:error, reason} when reason in [:invalid_page, :tenant_page_out_of_range] ->
        conn |> put_status(422) |> json(%{error: %{code: "invalid_page"}})

      {:error, _reason} ->
        conn
        |> put_status(503)
        |> json(%{error: %{code: "tenant_directory_unavailable"}})
    end
  end

  defp page_number(%{"page" => page}) when is_binary(page) do
    case Integer.parse(page) do
      {value, ""} when value > 0 -> {:ok, value}
      _invalid -> {:error, :invalid_page}
    end
  end

  defp page_number(%{"page" => _structured}), do: {:error, :invalid_page}

  defp page_number(_params), do: {:ok, 1}

  defp tenant_json(tenant) do
    %{
      key: tenant.key,
      name: tenant.name,
      created_at: DateTime.to_iso8601(tenant.inserted_at)
    }
  end
end
