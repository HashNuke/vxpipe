defmodule Vxpipe.Console.Test.NavigationRepository do
  @moduledoc false

  def create_tenant(owner, tenant) do
    send(owner, {:created_tenant, tenant})
    {:ok, tenant}
  end

  def tenant_candidates({owner, tenants, _calls}, scope, limit) do
    send(owner, {:candidates, scope, limit})

    case tenants do
      {:error, _} = error -> error
      tenants -> {:ok, tenants |> scoped(scope) |> Enum.take(limit)}
    end
  end

  def search_tenants({owner, tenants, _calls}, scope, query, limit, offset) do
    send(owner, {:search, scope, query, limit, offset})

    case tenants do
      {:error, _} = error ->
        error

      tenants ->
        rows =
          tenants
          |> scoped(scope)
          |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(query)))

        {:ok, {Enum.slice(rows, offset, limit), length(rows)}}
    end
  end

  def recent_calls({owner, _tenants, calls}, key, limit) do
    send(owner, {:recent_calls, key, limit})
    calls
  end

  defp scoped(tenants, :all), do: tenants
  defp scoped(tenants, {:keys, keys}), do: Enum.filter(tenants, &(&1.key in keys))
end
