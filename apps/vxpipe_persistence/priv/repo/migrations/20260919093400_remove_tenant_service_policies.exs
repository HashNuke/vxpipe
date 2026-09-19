defmodule Vxpipe.Persistence.Repo.Migrations.RemoveTenantServicePolicies do
  use Ecto.Migration

  def up do
    # Preserve credentials at both scopes. Every tenant credential now takes
    # precedence by presence, including rows formerly hidden by a policy.
    drop(table(:tenant_service_policies))
  end

  def down do
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
    FROM provider_credentials WHERE scope = 'tenant'
    """)
  end
end
