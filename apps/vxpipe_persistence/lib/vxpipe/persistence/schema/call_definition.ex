defmodule Vxpipe.Persistence.Schema.CallDefinition do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{DefinitionRevision, Tenant}

  schema "call_definitions" do
    field :public_id, :string
    field :published_at, :utc_datetime_usec

    belongs_to :tenant, Tenant
    belongs_to :published_revision, DefinitionRevision

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(definition, attributes) do
    definition
    |> cast(attributes, [:public_id, :tenant_id, :published_revision_id, :published_at])
    |> validate_required([:public_id, :tenant_id])
    |> validate_length(:public_id, min: 1, max: 128)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:published_revision_id)
    |> unique_constraint(:public_id, name: :call_definitions_tenant_id_public_id_index)
  end
end
