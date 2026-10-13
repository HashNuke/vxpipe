defmodule Vxpipe.Persistence.Schema.AuthenticationInstallation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.IdentityUser

  @primary_key {:key, :string, autogenerate: false}
  schema "authentication_installations" do
    field(:bootstrap_mode, :string)
    field(:setup_completed_at, :utc_datetime_usec)

    belongs_to(:initial_superadmin_user, IdentityUser)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(installation, attributes) do
    installation
    |> cast(attributes, [:key, :bootstrap_mode, :setup_completed_at, :initial_superadmin_user_id])
    |> validate_required([:key, :bootstrap_mode])
    |> validate_inclusion(:key, ["default"])
    |> validate_inclusion(:bootstrap_mode, ["first_run", "operator_required"])
    |> unique_constraint(:key)
    |> foreign_key_constraint(:initial_superadmin_user_id)
  end
end
