defmodule Vxpipe.Persistence.Schema.DefinitionRevision do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{CallDefinition, ParticipantRoute}

  schema "definition_revisions" do
    field :revision, :integer
    field :schema_version, :string
    field :source, :map
    field :source_digest, :string
    field :compiled_metadata, :map
    field :validation_errors, {:array, :map}

    belongs_to :call_definition, CallDefinition
    has_many :participant_routes, ParticipantRoute

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(revision, attributes) do
    revision
    |> cast(attributes, [
      :revision,
      :schema_version,
      :source,
      :source_digest,
      :compiled_metadata,
      :validation_errors,
      :call_definition_id
    ])
    |> validate_required([
      :revision,
      :schema_version,
      :source,
      :source_digest,
      :compiled_metadata,
      :validation_errors,
      :call_definition_id
    ])
    |> validate_number(:revision, greater_than: 0)
    |> validate_length(:schema_version, is: 11)
    |> validate_length(:source_digest, is: 64)
    |> foreign_key_constraint(:call_definition_id)
    |> unique_constraint(:revision,
      name: :definition_revisions_call_definition_id_revision_index
    )
  end
end
