defmodule Vxpipe.Persistence.Schema.IdentityPermission do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  schema "permissions" do
    field(:resource, :string)
    field(:scopes, {:array, :string})
    field(:mutating, :boolean)
    field(:requires_read, :string)
    field(:reserved, :boolean, default: false)
  end

  def changeset(permission, attributes) do
    permission
    |> cast(attributes, [:key, :resource, :scopes, :mutating, :requires_read, :reserved])
    |> validate_required([:key, :resource, :scopes])
    |> unique_constraint(:key)
  end
end
