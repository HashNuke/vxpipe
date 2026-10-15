defmodule Vxpipe.Gateway.TenantJSON do
  @moduledoc "Public tenant projections shared by product HTTP and MCP adapters."

  alias Vxpipe.Calls.{Tenant, TenantPage}

  def tenant(%Tenant{} = tenant) do
    Map.put(summary(tenant), :created_at, DateTime.to_iso8601(tenant.inserted_at))
  end

  def page(%TenantPage{} = page) do
    %{
      items: Enum.map(page.tenants, &summary/1),
      pagination: %{
        page: page.page,
        page_size: page.page_size,
        total: page.total,
        total_pages: page.total_pages
      }
    }
  end

  defp summary(%Tenant{} = tenant), do: %{tenant_key: tenant.key, name: tenant.name}
end
