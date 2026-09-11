defmodule Vxpipe.Persistence.Repo.Migrations.CreateCallArtifacts do
  use Ecto.Migration

  def change do
    create table(:call_artifacts) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:room_id, :uuid, null: false)
      add(:incarnation_id, :string, null: false)
      add(:kind, :string, null: false)
      add(:participant_id, :string)
      add(:connection_id, :string)
      add(:track_id, :string)
      add(:object_key, :text, null: false)
      add(:object_reference, :map)
      add(:sample_rate, :integer, null: false)
      add(:channels, :integer, null: false)
      add(:sample_format, :string, null: false)
      add(:started_offset_samples, :bigint)
      add(:ended_offset_samples, :bigint)
      add(:sample_count, :bigint, null: false)
      add(:accepted_chunks, :bigint, null: false)
      add(:rejected_chunks, :bigint, null: false)
      add(:gaps, :map, null: false)
      add(:status, :string, null: false)
      add(:terminal_reason, :string, null: false)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:call_artifacts, [:call_id, :public_id]))
    create(index(:call_artifacts, [:call_id, :kind]))

    create(
      constraint(:call_artifacts, :call_artifacts_kind,
        check: "kind IN ('full_mix', 'participant_track')"
      )
    )

    create(
      constraint(:call_artifacts, :call_artifacts_sample_format, check: "sample_format = 's16le'")
    )

    create(
      constraint(:call_artifacts, :call_artifacts_status,
        check: "status IN ('complete', 'incomplete')"
      )
    )

    create(
      constraint(:call_artifacts, :call_artifacts_channels,
        check: "sample_rate > 0 AND channels > 0 AND channels <= 8"
      )
    )

    create(
      constraint(:call_artifacts, :call_artifacts_progress,
        check:
          "sample_count >= 0 AND accepted_chunks >= 0 AND rejected_chunks >= 0 AND ((sample_count = 0 AND started_offset_samples IS NULL AND ended_offset_samples IS NULL) OR (sample_count > 0 AND started_offset_samples >= 0 AND ended_offset_samples > started_offset_samples AND sample_count <= ended_offset_samples - started_offset_samples))"
      )
    )

    create(
      constraint(:call_artifacts, :call_artifacts_source_identity,
        check:
          "(kind = 'full_mix' AND participant_id IS NULL AND connection_id IS NULL AND track_id IS NULL) OR (kind = 'participant_track' AND participant_id IS NOT NULL AND connection_id IS NOT NULL AND track_id IS NOT NULL)"
      )
    )

    create(
      constraint(:call_artifacts, :call_artifacts_complete_object,
        check: "status <> 'complete' OR object_reference IS NOT NULL"
      )
    )
  end
end
