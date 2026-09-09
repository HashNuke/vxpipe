defmodule Vxpipe.Persistence.Repo.Migrations.CreateTenantDefinitionControlPlane do
  use Ecto.Migration

  def change do
    create table(:tenants) do
      add :key, :string, null: false
      add :name, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:key])
    create constraint(:tenants, :tenants_key_shape,
             check: "char_length(key) = 16 AND key ~ '^[A-Za-z0-9_-]+$'"
           )

    create table(:api_keys) do
      add :public_id, :uuid, null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :scopes, {:array, :string}, null: false
      add :digest, :binary, null: false
      add :revoked_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:public_id])
    create unique_index(:api_keys, [:tenant_id, :digest])
    create index(:api_keys, [:tenant_id, :revoked_at])

    create constraint(:api_keys, :api_keys_scopes,
             check:
               "cardinality(scopes) > 0 AND scopes <@ ARRAY['admin', 'calls']::varchar[]"
           )

    create constraint(:api_keys, :api_keys_digest_size, check: "octet_length(digest) = 32")

    create table(:call_definitions) do
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false
      add :public_id, :string, null: false
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:call_definitions, [:tenant_id, :public_id])

    create table(:definition_revisions) do
      add :call_definition_id, references(:call_definitions, on_delete: :delete_all), null: false
      add :revision, :integer, null: false
      add :schema_version, :string, null: false
      add :source, :map, null: false
      add :source_digest, :string, size: 64, null: false
      add :compiled_metadata, :map, null: false
      add :validation_errors, {:array, :map}, null: false, default: []
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:definition_revisions, [:call_definition_id, :revision])

    alter table(:call_definitions) do
      add :published_revision_id,
          references(:definition_revisions, on_delete: :nilify_all)
    end

    create index(:call_definitions, [:published_revision_id])

    create table(:participant_routes) do
      add :public_id, :uuid, null: false
      add :tenant_id, references(:tenants, on_delete: :delete_all), null: false

      add :definition_revision_id,
          references(:definition_revisions, on_delete: :delete_all),
          null: false

      add :participant_ref, :string, null: false
      add :published_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:participant_routes, [:public_id])
    create unique_index(:participant_routes, [:definition_revision_id, :participant_ref])
    create index(:participant_routes, [:tenant_id, :public_id, :published_at])
  end
end
