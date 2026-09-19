defmodule Vxpipe.Persistence.Repo.Migrations.AddScopedProviderCredentials do
  use Ecto.Migration

  def up do
    alter table(:provider_credentials) do
      add(:scope, :string, null: false, default: "tenant")
      modify(:tenant_id, :bigint, null: true)
    end

    create(
      constraint(:provider_credentials, :provider_credentials_owner,
        check:
          "(scope = 'tenant' AND tenant_id IS NOT NULL) OR " <>
            "(scope = 'platform' AND tenant_id IS NULL)"
      )
    )

    create(
      unique_index(:provider_credentials, [:provider, :name],
        where: "scope = 'platform'",
        name: :provider_credentials_platform_provider_name_index
      )
    )

    create table(:tenant_service_policies) do
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:provider, :string, null: false)
      add(:name, :string, null: false)
      add(:policy, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:tenant_service_policies, [:tenant_id, :provider, :name]))

    create(
      constraint(:tenant_service_policies, :tenant_service_policies_policy,
        check: "policy IN ('override', 'disabled')"
      )
    )

    execute("""
    INSERT INTO tenant_service_policies (tenant_id, provider, name, policy, inserted_at, updated_at)
    SELECT tenant_id, provider, name, 'override', inserted_at, updated_at
    FROM provider_credentials
    """)
  end

  def down do
    # Reverting after platform use would silently change tenant resolution. Require
    # an explicit operator export/cutover instead of dropping live configuration.
    execute("""
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM provider_credentials WHERE scope = 'platform') OR
         EXISTS (SELECT 1 FROM tenant_service_policies WHERE policy = 'disabled') OR
         EXISTS (
           SELECT 1 FROM provider_credentials c
           WHERE NOT EXISTS (
             SELECT 1 FROM tenant_service_policies p
             WHERE p.tenant_id = c.tenant_id AND p.provider = c.provider
               AND p.name = c.name AND p.policy = 'override'
           )
         ) THEN
        RAISE EXCEPTION 'Scoped services require explicit cutover before rollback';
      END IF;
    END $$;
    """)

    drop(table(:tenant_service_policies))

    drop(
      index(:provider_credentials, [:provider, :name],
        name: :provider_credentials_platform_provider_name_index
      )
    )

    drop(constraint(:provider_credentials, :provider_credentials_owner))

    alter table(:provider_credentials) do
      remove(:scope)
      modify(:tenant_id, :bigint, null: false)
    end
  end
end
