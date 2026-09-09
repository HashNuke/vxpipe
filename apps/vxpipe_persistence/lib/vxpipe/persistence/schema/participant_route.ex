defmodule Vxpipe.Persistence.Schema.ParticipantRoute do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{DefinitionRevision, Tenant}

  schema "participant_routes" do
    field :public_id, Ecto.UUID
    field :participant_ref, :string
    field :published_at, :utc_datetime_usec

    belongs_to :tenant, Tenant
    belongs_to :definition_revision, DefinitionRevision

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(route, attributes) do
    route
    |> cast(attributes, [
      :public_id,
      :participant_ref,
      :published_at,
      :tenant_id,
      :definition_revision_id
    ])
    |> validate_required([:public_id, :participant_ref, :tenant_id, :definition_revision_id])
    |> validate_length(:participant_ref, min: 1, max: 128)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:definition_revision_id)
    |> unique_constraint(:public_id)
    |> unique_constraint(:participant_ref,
      name: :participant_routes_definition_revision_id_participant_ref_index
    )
  end
end
