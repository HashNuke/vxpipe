defmodule Vxpipe.Persistence.TenantDirectoryStore do
  @moduledoc "Scoped, bounded tenant lookup for browser navigation."

  import Ecto.Query

  alias Vxpipe.Calls.Tenant, as: DomainTenant
  alias Vxpipe.Persistence.Schema.Tenant

  def search(repo, scope, query, limit, offset) do
    filtered =
      scope
      |> scoped_query()
      |> where(
        [tenant],
        fragment("strpos(lower(?), lower(?)) > 0", tenant.name, ^query) or
          fragment("strpos(lower(?), lower(?)) > 0", tenant.key, ^query)
      )

    page =
      filtered
      |> ordered()
      |> limit(^limit)
      |> offset(^offset)
      |> select([tenant], %{key: tenant.key, name: tenant.name, inserted_at: tenant.inserted_at})

    totals = select(filtered, [tenant], %{value: count(tenant.id)})

    combined =
      from(total in subquery(totals),
        left_join: tenant in subquery(page),
        on: true,
        order_by: [asc: fragment("lower(?)", tenant.name), asc: tenant.key],
        select: {tenant.key, tenant.name, tenant.inserted_at, total.value}
      )

    repository_result(fn ->
      rows = repo.all(combined)
      [{_, _, _, total} | _] = rows

      tenants =
        for {key, name, inserted_at, _} <- rows,
            not is_nil(key),
            do: %DomainTenant{key: key, name: name, inserted_at: inserted_at}

      {:ok, {tenants, total}}
    end)
  end

  def candidates(repo, scope, limit) do
    query = scope |> scoped_query() |> ordered() |> limit(^limit)

    repository_result(fn ->
      {:ok,
       Enum.map(repo.all(query), fn tenant ->
         %DomainTenant{key: tenant.key, name: tenant.name, inserted_at: tenant.inserted_at}
       end)}
    end)
  end

  defp scoped_query(:all), do: from(tenant in Tenant)
  defp scoped_query({:keys, keys}), do: from(tenant in Tenant, where: tenant.key in ^keys)

  defp ordered(query),
    do: order_by(query, [tenant], asc: fragment("lower(?)", tenant.name), asc: tenant.key)

  defp repository_result(operation) do
    operation.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error, RuntimeError] ->
      {:error, :repository_unavailable}
  catch
    :exit, _reason -> {:error, :repository_unavailable}
  end
end
