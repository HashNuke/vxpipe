defmodule Vxpipe.Persistence.Schema.IdentityMembership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{IdentityUser, Tenant}

  schema "user_tenant_memberships" do
    field(:access_level, :string)

    belongs_to(:user, IdentityUser)
    belongs_to(:tenant, Tenant)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(membership, attributes) do
    membership
    |> cast(attributes, [:user_id, :tenant_id, :access_level])
    |> validate_required([:user_id, :tenant_id, :access_level])
    |> validate_inclusion(:access_level, ["read", "read_write"])
    |> unique_constraint([:user_id, :tenant_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:tenant_id)
  end
end
