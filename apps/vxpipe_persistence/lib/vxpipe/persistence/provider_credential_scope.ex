defmodule Vxpipe.Persistence.ProviderCredentialScope do
  @moduledoc false
  import Ecto.Query

  alias Vxpipe.Persistence.Schema.{Tenant, ProviderCredential}

  @private [log: false, telemetry_event: nil]

  def owner(repo, owner, lock \\ nil)
  def owner(_repo, :platform, _lock), do: {:ok, %{scope: "platform", key: nil, id: nil}}
  def owner(repo, {:tenant, key}, lock), do: owner(repo, key, lock)

  def owner(repo, key, lock) when is_binary(key) do
    query = from(t in Tenant, where: t.key == ^key)

    query =
      case lock do
        "FOR SHARE" -> from(t in query, lock: "FOR SHARE")
        "FOR UPDATE" -> from(t in query, lock: "FOR UPDATE")
        nil -> query
      end

    case repo.one(query, @private) do
      nil -> {:error, :tenant_not_found}
      tenant -> {:ok, %{scope: "tenant", key: tenant.key, id: tenant.id}}
    end
  end

  def owner(_repo, _owner, _lock), do: {:error, :invalid_tenant_key}

  def owned(query, %{scope: "platform"}),
    do: from(c in query, where: c.scope == "platform" and is_nil(c.tenant_id))

  def owned(query, %{scope: "tenant", id: id}),
    do: from(c in query, where: c.scope == "tenant" and c.tenant_id == ^id)

  def selected(repo, :platform, _provider, _name), do: owner(repo, :platform)
  def selected(repo, {:tenant, key}, provider, name), do: selected(repo, key, provider, name)

  def selected(repo, key, provider, name) do
    with {:ok, tenant} <- owner(repo, key, "FOR SHARE") do
      query = owned(ProviderCredential, tenant)

      exists? =
        repo.exists?(
          from(c in query, where: c.provider == ^provider and c.name == ^name),
          @private
        )

      if exists?, do: {:ok, tenant}, else: owner(repo, :platform)
    end
  end
end
