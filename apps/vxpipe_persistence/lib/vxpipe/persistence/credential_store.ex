defmodule Vxpipe.Persistence.CredentialStore do
  @moduledoc "Ecto adapter for tenant and API-key repository operations."

  @behaviour Vxpipe.Calls.CredentialRepository

  import Ecto.Query

  alias Vxpipe.Calls.Tenant, as: DomainTenant
  alias Vxpipe.Persistence.Schema.{ApiKey, Tenant}

  @impl true
  def bootstrap_tenant(repo, %DomainTenant{} = tenant, api_key) do
    repo.transaction(fn ->
      with {:ok, stored_tenant} <- insert_tenant(repo, tenant),
           {:ok, stored_key} <- insert_key(repo, stored_tenant, api_key) do
        {to_domain_tenant(stored_tenant), to_key_record(stored_key, tenant.key)}
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
  end

  @impl true
  def fetch_tenant(repo, tenant_key) do
    case repo.get_by(Tenant, key: tenant_key) do
      nil -> {:error, :not_found}
      tenant -> {:ok, to_domain_tenant(tenant)}
    end
  end

  @impl true
  def insert_api_key(repo, tenant_key, api_key) do
    case repo.get_by(Tenant, key: tenant_key) do
      nil ->
        {:error, :tenant_not_found}

      tenant ->
        case insert_key(repo, tenant, api_key) do
          {:ok, stored} -> {:ok, to_key_record(stored, tenant_key)}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def fetch_api_key(repo, tenant_key, digest) do
    query =
      from key in ApiKey,
        join: tenant in assoc(key, :tenant),
        where: tenant.key == ^tenant_key and key.digest == ^digest,
        select: {key, tenant.key}

    case repo.one(query) do
      nil -> {:error, :not_found}
      {key, key_tenant} -> {:ok, to_key_record(key, key_tenant)}
    end
  end

  @impl true
  def revoke_api_key(repo, tenant_key, api_key_id, revoked_at) do
    query =
      from key in ApiKey,
        join: tenant in assoc(key, :tenant),
        where: tenant.key == ^tenant_key and key.public_id == ^api_key_id,
        select: {key, tenant.key}

    case repo.one(query) do
      nil ->
        {:error, :not_found}

      {key, key_tenant} ->
        key
        |> ApiKey.changeset(%{revoked_at: key.revoked_at || revoked_at})
        |> repo.update()
        |> case do
          {:ok, stored} -> {:ok, to_key_record(stored, key_tenant)}
          {:error, _changeset} -> {:error, :credential_update_failed}
        end
    end
  end

  defp insert_tenant(repo, tenant) do
    %Tenant{}
    |> Tenant.changeset(%{key: tenant.key, name: tenant.name})
    |> repo.insert()
    |> case do
      {:ok, stored} -> {:ok, stored}
      {:error, changeset} -> {:error, tenant_error(changeset)}
    end
  end

  defp insert_key(repo, tenant, api_key) do
    attributes = %{
      public_id: api_key.id,
      tenant_id: tenant.id,
      name: api_key.name,
      scopes: external_scopes(api_key.scopes),
      digest: api_key.digest,
      revoked_at: api_key.revoked_at
    }

    %ApiKey{}
    |> ApiKey.changeset(attributes)
    |> repo.insert()
    |> case do
      {:ok, stored} -> {:ok, stored}
      {:error, changeset} -> {:error, api_key_error(changeset)}
    end
  end

  defp tenant_error(changeset) do
    if Keyword.has_key?(changeset.errors, :key),
      do: :tenant_key_conflict,
      else: :tenant_insert_failed
  end

  defp api_key_error(changeset) do
    cond do
      unique_error?(changeset, :public_id) -> :api_key_id_conflict
      unique_error?(changeset, :digest) -> :api_key_digest_conflict
      true -> :api_key_insert_failed
    end
  end

  defp unique_error?(changeset, field) do
    Enum.any?(Keyword.get_values(changeset.errors, field), fn
      {_message, metadata} -> Keyword.get(metadata, :constraint) == :unique
    end)
  end

  defp external_scopes(scopes) do
    scopes
    |> Enum.map(fn
      :admin -> "admin"
      :calls -> "calls"
    end)
    |> Enum.sort()
  end

  defp internal_scopes(scopes) do
    MapSet.new(scopes, fn
      "admin" -> :admin
      "calls" -> :calls
    end)
  end

  defp to_domain_tenant(tenant) do
    %DomainTenant{key: tenant.key, name: tenant.name, inserted_at: tenant.inserted_at}
  end

  defp to_key_record(key, tenant_key) do
    %{
      id: key.public_id,
      tenant_key: tenant_key,
      name: key.name,
      scopes: internal_scopes(key.scopes),
      digest: key.digest,
      revoked_at: key.revoked_at,
      inserted_at: key.inserted_at
    }
  end
end
