defmodule Vxpipe.Persistence.Schema.IdentityRolePermission do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{IdentityPermission, IdentityRole}

  schema "role_permissions" do
    field(:scope, :string)

    belongs_to(:role, IdentityRole)

    belongs_to(:permission, IdentityPermission,
      foreign_key: :permission_key,
      references: :key,
      type: :string
    )
  end

  def changeset(grant, attributes) do
    grant
    |> cast(attributes, [:role_id, :permission_key, :scope])
    |> validate_required([:role_id, :permission_key, :scope])
    |> validate_inclusion(:scope, ["installation", "all_tenants", "assigned_tenants"])
    |> unique_constraint([:role_id, :permission_key])
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:permission_key)
  end
end
