defmodule Vxpipe.Persistence.Repo.Migrations.NameRecordingTracks do
  use Ecto.Migration

  @old_identity "(kind = 'full_mix' AND participant_id IS NULL AND connection_id IS NULL AND track_id IS NULL) OR (kind = 'participant_track' AND participant_id IS NOT NULL AND connection_id IS NOT NULL AND track_id IS NOT NULL)"
  @track_identity "(kind IN ('full_mix', 'room_track') AND participant_id IS NULL AND participant_key IS NULL AND reconnection = 0 AND connection_id IS NULL AND track_id IS NULL) OR (kind = 'participant_track' AND participant_id IS NOT NULL AND connection_id IS NOT NULL AND track_id IS NOT NULL AND reconnection >= 0)"

  def up do
    alter table(:call_artifacts) do
      add(:participant_key, :string)
      add(:reconnection, :integer, null: false, default: 0)
    end

    drop(
      constraint(:call_artifacts, :call_artifacts_kind,
        check: "kind IN ('full_mix', 'participant_track')"
      )
    )

    drop(constraint(:call_artifacts, :call_artifacts_source_identity, check: @old_identity))

    create(
      constraint(:call_artifacts, :call_artifacts_kind,
        check: "kind IN ('full_mix', 'participant_track', 'room_track')"
      )
    )

    create(constraint(:call_artifacts, :call_artifacts_source_identity, check: @track_identity))
  end

  def down do
    # Restoring the old schema would discard the source identity of named tracks.
    execute("LOCK TABLE call_artifacts IN ACCESS EXCLUSIVE MODE")

    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM call_artifacts
                 WHERE kind = 'room_track' OR participant_key IS NOT NULL OR reconnection <> 0) THEN
        RAISE EXCEPTION 'Cannot downgrade while named recording tracks exist';
      END IF;
    END $$;
    """)

    drop(constraint(:call_artifacts, :call_artifacts_kind))
    drop(constraint(:call_artifacts, :call_artifacts_source_identity))

    create(
      constraint(:call_artifacts, :call_artifacts_kind,
        check: "kind IN ('full_mix', 'participant_track')"
      )
    )

    create(constraint(:call_artifacts, :call_artifacts_source_identity, check: @old_identity))

    alter table(:call_artifacts) do
      remove(:reconnection)
      remove(:participant_key)
    end
  end
end
