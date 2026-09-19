defmodule Vxpipe.Persistence.ProviderServiceDirectory do
  @moduledoc false
  import Ecto.Query

  alias Vxpipe.Persistence.{ProviderCredentialScope, ProviderCredentialStore}
  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant, TenantServicePolicy}

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

        policies = policies(repo, owner)

        names =
          (Map.keys(own) ++ Map.keys(platform) ++ Map.keys(policies))
          |> Enum.uniq()
          |> Enum.sort()

        %{
          tenant: tenant,
          bindings: Enum.map(names, &binding(context, owner, &1, own, platform, policies))
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

  defp policies(_repo, %{scope: "platform"}), do: %{}

  defp policies(repo, owner) do
    rows =
      repo.all(
        from(p in TenantServicePolicy, where: p.tenant_id == ^owner.id, limit: ^(@limit + 1)),
        @private
      )

    if length(rows) > @limit, do: repo.rollback(:service_directory_limit)
    Map.new(rows, &{{&1.provider, &1.name}, &1.policy})
  end

  defp binding(context, owner, {provider, name} = key, own, platform, policies) do
    policy = policy(owner.scope, Map.get(policies, key))
    source = if policy in [:platform, :inherit], do: :platform, else: :tenant
    selected = if source == :platform, do: Map.get(platform, key), else: Map.get(own, key)
    selected = if policy == :disabled, do: nil, else: selected
    tenant_key = if source == :tenant, do: owner.key

    %{
      provider: provider,
      name: name,
      policy: policy,
      source: source,
      status: status(context, selected, tenant_key, policy),
      credential_id: selected && selected.public_id,
      tenant_credential_id: if(owner.scope == "tenant", do: id(Map.get(own, key))),
      platform_available: Map.has_key?(platform, key),
      last_validated_at: selected && selected.last_validated_at,
      saved_fields: if(selected, do: fields(selected.auth_kind), else: [])
    }
  end

  defp id(nil), do: nil
  defp id(row), do: row.public_id
  defp fields("api_key"), do: ["api_key"]
  defp fields("account_sid_auth_token"), do: ["account_sid", "auth_token"]
  defp policy("platform", _policy), do: :platform
  defp policy("tenant", nil), do: :inherit
  defp policy("tenant", "override"), do: :override
  defp policy("tenant", "disabled"), do: :disabled
  defp status(_context, _row, _key, :disabled), do: :disabled
  defp status(_context, nil, _key, _policy), do: :unavailable

  defp status(context, row, key, _policy),
    do: ProviderCredentialStore.availability(context, row, key)
end
