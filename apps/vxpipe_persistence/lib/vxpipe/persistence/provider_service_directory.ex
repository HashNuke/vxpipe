defmodule Vxpipe.Persistence.ProviderServiceDirectory do
  @moduledoc false
  import Ecto.Query

  alias Vxpipe.Persistence.{ProviderCredentialScope, ProviderCredentialStore}
  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant}

  @private [log: false, telemetry_event: nil]
  @limit 500

  def list(context, scope) do
    repo = Keyword.fetch!(context, :repo)

    repo.transaction(
      fn ->
        owner =
          case ProviderCredentialScope.owner(repo, scope, "FOR SHARE") do
            {:ok, owner} -> owner
            {:error, reason} -> repo.rollback(reason)
          end

        tenant = tenant(repo, owner)
        own = credentials(repo, owner)

        platform =
          if owner.scope == "platform", do: own, else: credentials(repo, %{scope: "platform"})

        names =
          (Map.keys(own) ++ Map.keys(platform))
          |> Enum.uniq()
          |> Enum.sort()

        %{
          tenant: tenant,
          bindings: Enum.map(names, &binding(context, owner, &1, own, platform))
        }
      end,
      @private
    )
  end

  defp tenant(_repo, %{scope: "platform"}), do: nil

  defp tenant(repo, owner) do
    repo.one(
      from(t in Tenant, where: t.id == ^owner.id, select: %{key: t.key, name: t.name}),
      @private
    )
  end

  defp credentials(repo, owner) do
    query = ProviderCredentialScope.owned(ProviderCredential, owner)

    rows =
      repo.all(from(c in query, order_by: [c.provider, c.name], limit: ^(@limit + 1)), @private)

    if length(rows) > @limit, do: repo.rollback(:service_directory_limit)
    Map.new(rows, &{{&1.provider, &1.name}, &1})
  end

  defp binding(context, owner, {provider, name} = key, own, platform) do
    source = if owner.scope == "tenant" and Map.has_key?(own, key), do: :tenant, else: :platform
    selected = if source == :tenant, do: Map.fetch!(own, key), else: Map.fetch!(platform, key)
    tenant_key = if source == :tenant, do: owner.key
    setup = ProviderCredentialStore.setup_metadata(context, selected, tenant_key)

    %{
      provider: provider,
      name: name,
      source: source,
      status: setup.status,
      credential_id: selected.public_id,
      platform_available: Map.has_key?(platform, key),
      last_validated_at: selected.last_validated_at,
      saved_fields: setup.saved_fields
    }
  end
end
