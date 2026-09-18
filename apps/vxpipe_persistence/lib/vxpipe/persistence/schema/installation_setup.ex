defmodule Vxpipe.Persistence.Schema.InstallationSetup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  schema "installation_setups" do
    belongs_to(:demo_tenant, Vxpipe.Persistence.Schema.Tenant)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(setup, attributes) do
    setup
    |> cast(attributes, [:key, :demo_tenant_id])
    |> validate_required([:key, :demo_tenant_id])
    |> unique_constraint(:key)
    |> unique_constraint(:demo_tenant_id)
    |> foreign_key_constraint(:demo_tenant_id)
  end
end
