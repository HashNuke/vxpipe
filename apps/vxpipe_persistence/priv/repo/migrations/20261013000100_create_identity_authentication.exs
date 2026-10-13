defmodule Vxpipe.Persistence.Repo.Migrations.CreateIdentityAuthentication do
  use Ecto.Migration
  import Ecto.Query

  def up do
    create table(:roles) do
      add(:public_id, :uuid, null: false)
      add(:slug, :string, null: false)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:kind, :string)
      add(:revision, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:roles, [:public_id]))
    create(unique_index(:roles, [:slug]))

    create table(:permissions, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:resource, :string, null: false)
      add(:scopes, {:array, :string}, null: false)
      add(:mutating, :boolean, null: false)
      add(:requires_read, :string)
      add(:reserved, :boolean, null: false, default: false)
    end

    create table(:role_permissions, primary_key: false) do
      add(:role_id, references(:roles, on_delete: :delete_all), null: false, primary_key: true)

      add(
        :permission_key,
        references(:permissions, column: :key, type: :string, on_delete: :restrict),
        null: false,
        primary_key: true
      )

      add(:scope, :string, null: false)
    end

    create table(:users) do
      add(:public_id, :uuid, null: false)
      add(:email, :string, null: false)
      add(:normalized_email, :string, null: false)
      add(:password_hash, :string, null: false)
      add(:role_id, references(:roles, on_delete: :restrict), null: false)
      add(:disabled_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:users, [:public_id]))
    create(unique_index(:users, [:normalized_email]))
    create(index(:users, [:role_id]))

    create table(:user_tenant_memberships) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:tenant_id, references(:tenants, on_delete: :delete_all), null: false)
      add(:access_level, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:user_tenant_memberships, [:user_id, :tenant_id]))
    create(index(:user_tenant_memberships, [:tenant_id]))

    create table(:user_sessions) do
      add(:public_id, :uuid, null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:token_digest, :string, null: false)
      add(:issued_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:revoked_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:user_sessions, [:public_id]))
    create(unique_index(:user_sessions, [:token_digest]))
    create(index(:user_sessions, [:user_id]))

    create table(:authentication_installations, primary_key: false) do
      add(:key, :string, primary_key: true)
      add(:bootstrap_mode, :string, null: false)
      add(:setup_completed_at, :utc_datetime_usec)
      add(:initial_superadmin_user_id, references(:users, on_delete: :nilify_all))

      timestamps(type: :utc_datetime_usec)
    end

    create table(:user_access_events) do
      add(:actor_user_id, references(:users, on_delete: :nilify_all))
      add(:target_user_id, references(:users, on_delete: :nilify_all))
      add(:target_role_id, references(:roles, on_delete: :nilify_all))
      add(:action, :string, null: false)
      add(:summary, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:user_access_events, [:actor_user_id]))
    create(index(:user_access_events, [:target_user_id]))

    create table(:authentication_setup_proofs) do
      add(:proof_digest, :string, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:used_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(unique_index(:authentication_setup_proofs, [:proof_digest]))

    create table(:authentication_attempts) do
      add(:normalized_account, :string, null: false)
      add(:client_address, :string, null: false)
      add(:attempted_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:authentication_attempts, [:normalized_account, :attempted_at]))
    create(index(:authentication_attempts, [:client_address, :attempted_at]))

    flush()
    seed_permissions()
    seed_roles()
    seed_installation_singleton()
  end

  def down do
    drop(table(:authentication_attempts))
    drop(table(:authentication_setup_proofs))
    drop(table(:user_access_events))
    drop(table(:authentication_installations))
    drop(table(:user_sessions))
    drop(table(:user_tenant_memberships))
    drop(table(:users))
    drop(table(:role_permissions))
    drop(table(:permissions))
    drop(table(:roles))
  end

  defp seed_permissions do
    entries = [
      {"calls.read", "calls", ["all_tenants", "assigned_tenants"], false, nil, false},
      {"calls.write", "calls", ["all_tenants", "assigned_tenants"], true, "calls.read", false},
      {"call_specs.read", "call_specs", ["all_tenants", "assigned_tenants"], false, nil, false},
      {"call_specs.write", "call_specs", ["all_tenants", "assigned_tenants"], true,
       "call_specs.read", false},
      {"call_specs.use_platform_services", "call_specs", ["installation"], false, nil, false},
      {"platform_services.read", "platform_services", ["installation"], false, nil, false},
      {"platform_services.write", "platform_services", ["installation"], true,
       "platform_services.read", false},
      {"tenant_services.read", "tenant_services", ["installation"], false, nil, false},
      {"tenant_services.write", "tenant_services", ["installation"], true, "tenant_services.read",
       false},
      {"tenant_api_keys.read", "tenant_api_keys", ["installation"], false, nil, false},
      {"tenant_api_keys.write", "tenant_api_keys", ["installation"], true, "tenant_api_keys.read",
       false},
      {"tenants.read", "tenants", ["installation"], false, nil, false},
      {"tenants.write", "tenants", ["installation"], true, "tenants.read", false},
      {"diagnostics.read", "diagnostics", ["installation"], false, nil, true},
      {"users.read", "users", ["installation"], false, nil, false},
      {"users.members.write", "users", ["installation"], true, "users.read", true},
      {"users.admins.write", "users", ["installation"], true, "users.read", true},
      {"users.superadmins.write", "users", ["installation"], true, "users.read", true}
    ]

    rows =
      Enum.map(entries, fn {key, resource, scopes, mutating, requires_read, reserved} ->
        %{
          key: key,
          resource: resource,
          scopes: scopes,
          mutating: mutating,
          requires_read: requires_read,
          reserved: reserved
        }
      end)

    {_, _} = repo().insert_all("permissions", rows, on_conflict: :nothing)

    :ok
  end

  defp seed_roles do
    superadmin_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    admin_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    platform_manager_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    tenant_manager_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    tenant_member_id = Ecto.UUID.dump!(Ecto.UUID.generate())

    roles = [
      %{
        public_id: superadmin_id,
        slug: "superadmin",
        name: "Superadmin",
        description: "Protected built-in with full platform and account authority.",
        kind: "superadmin",
        revision: 1,
        inserted_at: utc_now(),
        updated_at: utc_now()
      },
      %{
        public_id: admin_id,
        slug: "admin",
        name: "Admin",
        description:
          "Protected built-in with full operational access and ordinary account management.",
        kind: "admin",
        revision: 1,
        inserted_at: utc_now(),
        updated_at: utc_now()
      },
      %{
        public_id: platform_manager_id,
        slug: "platform-manager",
        name: "Platform Manager",
        description:
          "Editable template with platform and tenant operational access. No account management.",
        kind: nil,
        revision: 1,
        inserted_at: utc_now(),
        updated_at: utc_now()
      },
      %{
        public_id: tenant_manager_id,
        slug: "tenant-manager",
        name: "Tenant Manager",
        description:
          "Editable template with tenant operational access and platform read. No account management.",
        kind: nil,
        revision: 1,
        inserted_at: utc_now(),
        updated_at: utc_now()
      },
      %{
        public_id: tenant_member_id,
        slug: "tenant-member",
        name: "Tenant Member",
        description: "Editable template with assigned-tenant calls and call-spec access.",
        kind: nil,
        revision: 1,
        inserted_at: utc_now(),
        updated_at: utc_now()
      }
    ]

    repo().insert_all("roles", roles, on_conflict: :nothing)

    by_slug =
      from(r in "roles", select: {r.slug, r.id})
      |> repo().all()
      |> Map.new()

    grants =
      [
        {"platform-manager", "calls.read", "all_tenants"},
        {"platform-manager", "calls.write", "all_tenants"},
        {"platform-manager", "call_specs.read", "all_tenants"},
        {"platform-manager", "call_specs.write", "all_tenants"},
        {"platform-manager", "call_specs.use_platform_services", "installation"},
        {"platform-manager", "platform_services.read", "installation"},
        {"platform-manager", "platform_services.write", "installation"},
        {"platform-manager", "tenant_services.read", "installation"},
        {"platform-manager", "tenant_services.write", "installation"},
        {"platform-manager", "tenant_api_keys.read", "installation"},
        {"platform-manager", "tenant_api_keys.write", "installation"},
        {"platform-manager", "tenants.read", "installation"},
        {"platform-manager", "tenants.write", "installation"},
        {"tenant-manager", "calls.read", "all_tenants"},
        {"tenant-manager", "calls.write", "all_tenants"},
        {"tenant-manager", "call_specs.read", "all_tenants"},
        {"tenant-manager", "call_specs.write", "all_tenants"},
        {"tenant-manager", "call_specs.use_platform_services", "installation"},
        {"tenant-manager", "platform_services.read", "installation"},
        {"tenant-manager", "tenant_services.read", "installation"},
        {"tenant-manager", "tenant_services.write", "installation"},
        {"tenant-manager", "tenant_api_keys.read", "installation"},
        {"tenant-manager", "tenant_api_keys.write", "installation"},
        {"tenant-manager", "tenants.read", "installation"},
        {"tenant-manager", "tenants.write", "installation"},
        {"tenant-member", "calls.read", "assigned_tenants"},
        {"tenant-member", "calls.write", "assigned_tenants"},
        {"tenant-member", "call_specs.read", "assigned_tenants"},
        {"tenant-member", "call_specs.write", "assigned_tenants"}
      ]

    rows =
      for {slug, permission, scope} <- grants, role_id = by_slug[slug], not is_nil(role_id) do
        %{role_id: role_id, permission_key: permission, scope: scope}
      end

    repo().insert_all("role_permissions", rows, on_conflict: :nothing)
    :ok
  end

  defp seed_installation_singleton do
    mode = if pre_auth_records?(), do: "operator_required", else: "first_run"
    now = utc_now()

    repo().insert_all(
      "authentication_installations",
      [%{key: "default", bootstrap_mode: mode, inserted_at: now, updated_at: now}],
      on_conflict: :nothing
    )

    :ok
  end

  defp pre_auth_records? do
    tables = ["tenants", "installation_setups", "operator_login_challenges", "operator_api_keys"]

    Enum.any?(tables, fn table ->
      case repo().query("SELECT COUNT(*) FROM #{table}", []) do
        {:ok, %{rows: [[count]]}} -> count > 0
        _ -> false
      end
    end)
  end

  defp utc_now, do: DateTime.utc_now()
end
