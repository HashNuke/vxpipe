defmodule Vxpipe.Persistence.TestRevokingTelephonyServiceRepository do
  @moduledoc false

  import Ecto.Query

  alias Vxpipe.Persistence.TelephonyServiceStore
  alias Vxpipe.Persistence.Schema.ProviderCredential

  def resolve(context, tenant_key, name) do
    result = TelephonyServiceStore.resolve(context, tenant_key, name)

    if Agent.get_and_update(Keyword.fetch!(context, :revocation_switch), &{&1, false}) do
      {:ok, snapshot} = result
      repo = Keyword.fetch!(context, :repo)

      repo.update_all(
        from(c in ProviderCredential, where: c.public_id == ^snapshot.service.credential_id),
        set: [status: "revoked"]
      )
    end

    result
  end

  defdelegate with_active(context, tenant_key, requirements, operation), to: TelephonyServiceStore
end
