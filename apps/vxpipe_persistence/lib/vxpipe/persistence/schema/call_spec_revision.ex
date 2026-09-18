defmodule Vxpipe.Persistence.Schema.CallSpecRevision do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.{CallSpec, ParticipantRoute, TelephonyRoute}

  schema "call_spec_revisions" do
    field :revision, :integer
    field :schema_version, :string
    field :source, :map
    field :source_digest, :string
    field :compiled_metadata, :map
    field :validation_errors, {:array, :map}

    belongs_to :call_spec, CallSpec
    has_many :participant_routes, ParticipantRoute
    has_many :telephony_routes, TelephonyRoute

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
      :call_spec_id
    ])
    |> validate_required([
      :revision,
      :schema_version,
      :source,
      :source_digest,
      :compiled_metadata,
      :validation_errors,
      :call_spec_id
    ])
    |> validate_number(:revision, greater_than: 0)
    |> validate_length(:schema_version, is: 11)
    |> validate_length(:source_digest, is: 64)
    |> foreign_key_constraint(:call_spec_id)
    |> unique_constraint(:revision,
      name: :call_spec_revisions_call_spec_id_revision_index
    )
  end
end
