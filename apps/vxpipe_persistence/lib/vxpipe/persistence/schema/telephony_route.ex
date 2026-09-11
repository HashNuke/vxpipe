defmodule Vxpipe.Persistence.Schema.TelephonyRoute do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{DefinitionRevision, Tenant}

  schema "telephony_routes" do
    field :participant_ref, :string
    field :service, :string
    field :number, :string
    field :published_at, :utc_datetime_usec

    belongs_to :tenant, Tenant
    belongs_to :definition_revision, DefinitionRevision

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(route, attributes) do
    route
    |> cast(attributes, [
      :participant_ref,
      :service,
      :number,
      :published_at,
      :tenant_id,
      :definition_revision_id
    ])
    |> validate_required([
      :participant_ref,
      :service,
      :number,
      :tenant_id,
      :definition_revision_id
    ])
    |> validate_length(:participant_ref, min: 1, max: 128)
    |> validate_length(:service, min: 1, max: 128)
    |> validate_length(:number, min: 2, max: 16)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:definition_revision_id)
    |> unique_constraint(:participant_ref,
      name: :telephony_routes_definition_revision_id_participant_ref_index
    )
  end
end
