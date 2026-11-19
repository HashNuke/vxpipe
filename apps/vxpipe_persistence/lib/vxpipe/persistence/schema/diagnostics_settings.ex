defmodule Vxpipe.Persistence.Schema.DiagnosticsSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:key, :string, autogenerate: false}
  schema "installation_diagnostics_settings" do
    field(:enabled, :boolean, default: false)
    field(:revision, :integer, default: 0)
    field(:updated_by, Ecto.UUID)
    field(:updated_at, :utc_datetime_usec)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :revision, :updated_by, :updated_at])
    |> validate_required([:enabled, :revision, :updated_by, :updated_at])
    |> validate_number(:revision, greater_than: 0)
    |> check_constraint(:revision, name: :diagnostics_settings_revision)
    |> check_constraint(:revision, name: :diagnostics_settings_attribution)
  end
end
