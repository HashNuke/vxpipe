defmodule Vxpipe.Persistence.Repo.Migrations.AddCallSpecPublications do
  use Ecto.Migration

  def up do
    alter table(:call_specs) do
      add(:published_version, :integer)
    end

    create table(:call_spec_publications) do
      add(:call_spec_id, references(:call_specs, on_delete: :delete_all), null: false)

      add(:call_spec_revision_id, references(:call_spec_revisions, on_delete: :restrict),
        null: false
      )

      add(:version, :integer, null: false)
      add(:published_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:call_spec_publications, [:call_spec_id, :version]))

    create(
      constraint(:call_spec_publications, :positive_publication_version, check: "version > 0")
    )

    execute("""
    INSERT INTO call_spec_publications (call_spec_id, call_spec_revision_id, version, published_at)
    SELECT s.id, r.id, r.revision, s.published_at
    FROM call_specs s JOIN call_spec_revisions r ON r.id = s.published_revision_id
    WHERE s.published_at IS NOT NULL
    """)

    execute("""
    UPDATE call_specs s SET published_version = p.version
    FROM call_spec_publications p WHERE p.call_spec_id = s.id
    """)
  end

  def down do
    drop(table(:call_spec_publications))

    alter table(:call_specs) do
      remove(:published_version)
    end
  end
end
