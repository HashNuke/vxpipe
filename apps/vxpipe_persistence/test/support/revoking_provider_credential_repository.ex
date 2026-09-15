defmodule Vxpipe.Persistence.TestRevokingProviderCredentialRepository do
  @moduledoc false

  import Ecto.Query
  alias Vxpipe.Persistence.ProviderCredentialStore
  alias Vxpipe.Persistence.Schema.{ProviderCredential, Tenant}

  def resolve(context, tenant_key, provider, name) do
    result = ProviderCredentialStore.resolve(context, tenant_key, provider, name)
    switch = Keyword.fetch!(context, :revocation_switch)

    if Agent.get_and_update(switch, &{&1, false}) do
      repo = Keyword.fetch!(context, :repo)

      query =
        from(c in ProviderCredential,
          join: tenant in Tenant,
          on: tenant.id == c.tenant_id,
          where: tenant.key == ^tenant_key and c.provider == ^provider and c.name == ^name
        )

      {1, _} = repo.update_all(query, set: [status: "revoked"])
    end

    result
  end

  defdelegate with_active(context, tenant_key, requirements, operation),
    to: ProviderCredentialStore
end
