defmodule Vxpipe.Persistence.Schema.TenantServicePolicy do
  use Ecto.Schema

  schema "tenant_service_policies" do
    belongs_to(:tenant, Vxpipe.Persistence.Schema.Tenant)
    field(:provider, :string)
    field(:name, :string)
    field(:policy, :string)
    timestamps(type: :utc_datetime_usec)
  end
end
