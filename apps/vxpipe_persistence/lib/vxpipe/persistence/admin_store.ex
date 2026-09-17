defmodule Vxpipe.Persistence.AdminStore do
  @moduledoc "Ecto adapter for installation-operator read workflows."

  @behaviour Vxpipe.Calls.AdminRepository

  import Ecto.Query

  alias Vxpipe.Calls.Tenant, as: DomainTenant
  alias Vxpipe.Persistence.Schema.Tenant

  @impl true
  def list_tenants(repo, limit, offset) do
    page_query =
      from(tenant in Tenant,
        order_by: [desc: tenant.inserted_at, desc: tenant.key],
        limit: ^limit,
        offset: ^offset,
        select: %{
          key: tenant.key,
          name: tenant.name,
          inserted_at: tenant.inserted_at
        }
      )

    total_query = from(tenant in Tenant, select: %{value: count(tenant.id)})

    query =
      from(total in subquery(total_query),
        left_join: tenant in subquery(page_query),
        on: true,
        order_by: [desc: tenant.inserted_at, desc: tenant.key],
        select: {tenant.key, tenant.name, tenant.inserted_at, total.value}
      )

    try do
      query
      |> repo.all()
      |> tenant_page()
    rescue
      _error in [DBConnection.ConnectionError, Postgrex.Error, RuntimeError] ->
        {:error, :repository_unavailable}
    catch
      :exit, _reason -> {:error, :repository_unavailable}
    end
  end

  defp tenant_page([{nil, nil, nil, total}]), do: {:ok, {[], total}}

  defp tenant_page(rows) do
    {tenants, totals} =
      Enum.map_reduce(rows, [], fn {key, name, inserted_at, total}, totals ->
        {%DomainTenant{key: key, name: name, inserted_at: inserted_at}, [total | totals]}
      end)

    case Enum.uniq(totals) do
      [total] -> {:ok, {tenants, total}}
      _inconsistent -> {:error, :repository_unavailable}
    end
  end
end
