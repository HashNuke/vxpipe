defmodule Vxpipe.Persistence.Repo.Migrations.AddSettingsAccessKeys do
  use Ecto.Migration

  def up do
    alter table(:api_keys) do
      modify(:tenant_id, :bigint, null: true)
      add(:last_four, :string, size: 4)
    end

    drop(constraint(:api_keys, :api_keys_scopes))

    create(
      constraint(:api_keys, :api_keys_scopes,
        check:
          "(tenant_id IS NULL AND scopes = ARRAY['platform']::varchar[]) OR (tenant_id IS NOT NULL AND cardinality(scopes) > 0 AND scopes <@ ARRAY['admin','calls']::varchar[])"
      )
    )

    create(
      unique_index(:api_keys, [:digest],
        where: "tenant_id IS NULL",
        name: :platform_api_keys_digest_index
      )
    )

    flush()

    entries = [
      %{
        key: "access_keys.read",
        resource: "access_keys",
        scopes: ["all_tenants", "assigned_tenants"],
        mutating: false,
        requires_read: nil,
        reserved: false
      },
      %{
        key: "access_keys.write",
        resource: "access_keys",
        scopes: ["all_tenants", "assigned_tenants"],
        mutating: true,
        requires_read: "access_keys.read",
        reserved: false
      },
      %{
        key: "platform_api_keys.read",
        resource: "platform_api_keys",
        scopes: ["installation"],
        mutating: false,
        requires_read: nil,
        reserved: false
      },
      %{
        key: "platform_api_keys.write",
        resource: "platform_api_keys",
        scopes: ["installation"],
        mutating: true,
        requires_read: "platform_api_keys.read",
        reserved: true
      }
    ]

    repo().insert_all("permissions", entries, on_conflict: :nothing)
    # Built-in grants are resolved from the catalog; custom roles opt into new grants.
  end

  def down do
    raise Ecto.MigrationError,
          "access keys and granted permissions require explicit migration before rollback"
  end
end
