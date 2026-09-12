defmodule Vxpipe.Persistence.Schema.CallDetailsPublication do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:source_digest, :checksum, :contents, :object_reference]}

  schema "call_details_publications" do
    field(:public_id, :string)
    field(:schema_version, :string)
    field(:source_digest, :binary)
    field(:recorded_at, :utc_datetime_usec)
    field(:filename, :string)
    field(:completeness, Ecto.Enum, values: [:complete, :incomplete])
    field(:checksum, :binary)
    field(:contents, :binary)
    field(:status, Ecto.Enum, values: [:pending, :published])
    field(:object_key, :string)
    field(:object_reference, :map)
    field(:published_at, :utc_datetime_usec)
    belongs_to(:call, Call)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def reserve_changeset(publication, attributes) do
    publication
    |> cast(attributes, [
      :public_id,
      :call_id,
      :schema_version,
      :source_digest,
      :recorded_at,
      :filename,
      :completeness,
      :checksum,
      :contents,
      :status
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :schema_version,
      :source_digest,
      :recorded_at,
      :filename,
      :completeness,
      :checksum,
      :contents,
      :status
    ])
    |> apply_validations()
  end

  def publish_changeset(publication, attributes) do
    publication
    |> cast(attributes, [:status, :object_key, :object_reference, :published_at])
    |> validate_required([:status, :object_key, :object_reference, :published_at])
    |> apply_validations()
  end

  defp apply_validations(changeset) do
    changeset
    |> validate_length(:public_id, min: 1, max: 256)
    |> validate_length(:schema_version, min: 1, max: 32)
    |> validate_length(:filename, min: 1, max: 64)
    |> validate_length(:object_key, min: 1, max: 1_024)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint(:public_id)
    |> unique_constraint([:call_id, :source_digest])
    |> unique_constraint([:call_id, :filename])
    |> check_constraint(:source_digest, name: :call_details_publications_digest_sizes)
    |> check_constraint(:completeness, name: :call_details_publications_completeness)
    |> check_constraint(:status, name: :call_details_publications_status)
    |> check_constraint(:status, name: :call_details_publications_delivery)
  end
end
