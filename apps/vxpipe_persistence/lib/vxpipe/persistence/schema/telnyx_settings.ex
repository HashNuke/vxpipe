defmodule Vxpipe.Persistence.Schema.TelnyxSettings do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "telnyx_settings" do
    field(:application_id, :string)
  end

  def changeset(settings, application_id) do
    settings
    |> change(application_id: application_id)
    |> validate_format(:application_id, ~r/\A[\x21-\x7E]{1,128}\z/)
  end
end
