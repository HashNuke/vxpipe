defmodule Vxpipe.Persistence.Repo.Migrations.CreateCallDetailsPublications do
  use Ecto.Migration

  def change do
    create table(:call_details_publications) do
      add(:public_id, :string, null: false)
      add(:call_id, references(:calls, on_delete: :delete_all), null: false)
      add(:schema_version, :string, null: false)
      add(:source_digest, :binary, null: false)
      add(:recorded_at, :utc_datetime_usec, null: false)
      add(:filename, :string, null: false)
      add(:completeness, :string, null: false)
      add(:checksum, :binary, null: false)
      add(:contents, :binary, null: false)
      add(:status, :string, null: false)
      add(:object_key, :text)
      add(:object_reference, :map)
      add(:published_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:call_details_publications, [:public_id]))
    create(unique_index(:call_details_publications, [:call_id, :source_digest]))
    create(unique_index(:call_details_publications, [:call_id, :filename]))
    create(index(:call_details_publications, [:call_id, :recorded_at]))

    create(
      constraint(:call_details_publications, :call_details_publications_digest_sizes,
        check: "octet_length(source_digest) = 32 AND octet_length(checksum) = 32"
      )
    )

    create(
      constraint(:call_details_publications, :call_details_publications_completeness,
        check: "completeness IN ('complete', 'incomplete')"
      )
    )

    create(
      constraint(:call_details_publications, :call_details_publications_status,
        check: "status IN ('pending', 'published')"
      )
    )

    create(
      constraint(:call_details_publications, :call_details_publications_delivery,
        check:
          "(status = 'pending' AND object_key IS NULL AND object_reference IS NULL AND published_at IS NULL) OR (status = 'published' AND object_key IS NOT NULL AND object_reference IS NOT NULL AND published_at IS NOT NULL)"
      )
    )

    alter table(:calls) do
      add(
        :latest_details_publication_id,
        references(:call_details_publications, on_delete: :nilify_all)
      )
    end

    create(index(:calls, [:latest_details_publication_id]))
  end
end
