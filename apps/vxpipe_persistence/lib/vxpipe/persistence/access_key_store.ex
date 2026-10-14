defmodule Vxpipe.Persistence.AccessKeyStore do
  @moduledoc "Database-scoped access-key inventory and hash-only persistence."
  @behaviour Vxpipe.Calls.AccessKeyRepository
  import Ecto.Query
  alias Vxpipe.Persistence.Schema.{ApiKey, Tenant}
  @private [log: false, telemetry_event: nil]

  @impl true
  def list(repo, scope, platform?, page) do
    safely(fn ->
      query =
        from(k in ApiKey,
          left_join: t in Tenant,
          on: t.id == k.tenant_id,
          where: is_nil(k.revoked_at)
        )

      query = scoped_keys(query, scope, platform?)

      query =
        if page.query == "",
          do: query,
          else:
            where(
              query,
              [k, t],
              ilike(k.name, ^pattern(page.query)) or ilike(t.name, ^pattern(page.query))
            )

      total = repo.aggregate(query, :count, :id, @private)

      keys =
        repo.all(
          from([k, t] in query,
            order_by: [desc: k.inserted_at, desc: k.id],
            limit: ^page.limit,
            offset: ^page.offset,
            select: {k, t}
          ),
          @private
        )
        |> Enum.map(fn {key, tenant} -> metadata(key, tenant) end)

      {:ok, %{keys: keys, total: total, page: page.page, page_size: page.limit}}
    end)
  end

  @impl true
  def tenants(repo, scope, page) do
    safely(fn ->
      query = scoped_tenants(Tenant, scope)

      query =
        if page.query == "",
          do: query,
          else:
            where(
              query,
              [t],
              ilike(t.name, ^pattern(page.query)) or ilike(t.key, ^pattern(page.query))
            )

      total = repo.aggregate(query, :count, :id, @private)

      tenants =
        repo.all(
          from(t in query,
            order_by: [asc: t.name, asc: t.id],
            limit: ^page.limit,
            offset: ^page.offset,
            select: %{key: t.key, name: t.name}
          ),
          @private
        )

      {:ok, %{tenants: tenants, total: total, page: page.page, page_size: page.limit}}
    end)
  end

  @impl true
  def insert(repo, record) do
    safely(fn ->
      tenant = if record.tenant_key, do: repo.get_by(Tenant, [key: record.tenant_key], @private)

      if record.tenant_key && is_nil(tenant) do
        {:error, :tenant_not_found}
      else
        attrs = %{
          public_id: record.id,
          name: record.name,
          tenant_id: tenant && tenant.id,
          scopes: record.scopes,
          digest: record.digest,
          last_four: record.last_four
        }

        case repo.insert(ApiKey.changeset(%ApiKey{}, attrs), @private) do
          {:ok, key} -> {:ok, metadata(key, tenant)}
          {:error, _} -> {:error, :key_creation_failed}
        end
      end
    end)
  end

  @impl true
  def fetch(repo, id) do
    safely(fn ->
      with {:ok, id} <- Ecto.UUID.cast(id),
           {key, tenant} <-
             repo.one(
               from(k in ApiKey,
                 left_join: t in Tenant,
                 on: t.id == k.tenant_id,
                 where: k.public_id == ^id and is_nil(k.revoked_at),
                 select: {k, t}
               ),
               @private
             ) do
        {:ok, metadata(key, tenant)}
      else
        _ -> {:error, :not_found}
      end
    end)
  end

  @impl true
  def revoke(repo, id, now) do
    safely(fn ->
      repo.update_all(
        from(k in ApiKey, where: k.public_id == ^id and is_nil(k.revoked_at)),
        [set: [revoked_at: now, updated_at: now]],
        @private
      )

      :ok
    end)
  end

  @impl true
  def authenticate_platform(repo, digest) do
    safely(fn ->
      case repo.one(
             from(k in ApiKey,
               where:
                 is_nil(k.tenant_id) and k.scopes == ^["platform"] and
                   k.digest == ^digest and is_nil(k.revoked_at),
               select: k.public_id
             ),
             @private
           ) do
        nil -> {:error, :invalid_api_key}
        id -> {:ok, id}
      end
    end)
  end

  defp scoped_keys(query, :all, true), do: query
  defp scoped_keys(query, :all, false), do: where(query, [k], not is_nil(k.tenant_id))

  defp scoped_keys(query, {:keys, keys}, true),
    do: where(query, [k, t], is_nil(k.tenant_id) or t.key in ^keys)

  defp scoped_keys(query, {:keys, keys}, false), do: where(query, [_k, t], t.key in ^keys)
  defp scoped_tenants(query, :all), do: query
  defp scoped_tenants(query, {:keys, keys}), do: where(query, [t], t.key in ^keys)

  defp metadata(key, tenant) do
    kind =
      cond do
        is_nil(tenant) -> "platform"
        "admin" in key.scopes and "calls" in key.scopes -> "full"
        "admin" in key.scopes -> "legacy_admin"
        true -> "calls"
      end

    %{
      id: key.public_id,
      name: key.name,
      kind: kind,
      last_four: key.last_four,
      created_at: key.inserted_at,
      tenant: if(tenant, do: %{key: tenant.key, name: tenant.name})
    }
  end

  defp pattern(query),
    do:
      "%" <>
        (query
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

  defp safely(fun) do
    fun.()
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, :repository_unavailable}
  end
end
