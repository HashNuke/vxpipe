defmodule Vxpipe.Persistence.Schema.CallArtifact do
  use Ecto.Schema
  import Ecto.Changeset

  alias Vxpipe.Persistence.Schema.Call

  @derive {Inspect, except: [:object_reference]}

  schema "call_artifacts" do
    field(:public_id, :string)
    field(:room_id, Ecto.UUID)
    field(:incarnation_id, :string)
    field(:kind, Ecto.Enum, values: [:full_mix, :participant_track])
    field(:participant_id, :string)
    field(:connection_id, :string)
    field(:track_id, :string)
    field(:object_key, :string)
    field(:object_reference, :map)
    field(:sample_rate, :integer)
    field(:channels, :integer)
    field(:sample_format, Ecto.Enum, values: [:s16le])
    field(:started_offset_samples, :integer)
    field(:ended_offset_samples, :integer)
    field(:sample_count, :integer)
    field(:accepted_chunks, :integer)
    field(:rejected_chunks, :integer)
    field(:gaps, :map)
    field(:status, Ecto.Enum, values: [:complete, :incomplete])
    field(:terminal_reason, :string)

    belongs_to(:call, Call)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(artifact, attributes) do
    artifact
    |> cast(attributes, [
      :public_id,
      :call_id,
      :room_id,
      :incarnation_id,
      :kind,
      :participant_id,
      :connection_id,
      :track_id,
      :object_key,
      :object_reference,
      :sample_rate,
      :channels,
      :sample_format,
      :started_offset_samples,
      :ended_offset_samples,
      :sample_count,
      :accepted_chunks,
      :rejected_chunks,
      :gaps,
      :status,
      :terminal_reason
    ])
    |> validate_required([
      :public_id,
      :call_id,
      :room_id,
      :incarnation_id,
      :kind,
      :object_key,
      :sample_rate,
      :channels,
      :sample_format,
      :sample_count,
      :accepted_chunks,
      :rejected_chunks,
      :gaps,
      :status,
      :terminal_reason
    ])
    |> validate_length(:public_id, min: 1, max: 256)
    |> validate_length(:incarnation_id, min: 1, max: 256)
    |> validate_length(:object_key, min: 1, max: 1_024)
    |> validate_length(:terminal_reason, min: 1, max: 256)
    |> foreign_key_constraint(:call_id)
    |> unique_constraint([:call_id, :public_id])
    |> check_constraint(:kind, name: :call_artifacts_kind)
    |> check_constraint(:sample_format, name: :call_artifacts_sample_format)
    |> check_constraint(:status, name: :call_artifacts_status)
    |> check_constraint(:channels, name: :call_artifacts_channels)
    |> check_constraint(:sample_count, name: :call_artifacts_progress)
    |> check_constraint(:kind, name: :call_artifacts_source_identity)
    |> check_constraint(:status, name: :call_artifacts_complete_object)
  end
end
