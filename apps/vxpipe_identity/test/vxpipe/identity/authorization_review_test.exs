defmodule Vxpipe.Identity.AuthorizationReviewTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Identity.{Accounts, Authorization, Permission, Roles}

  @write_keys ["users.members.write", "users.admins.write", "users.superadmins.write"]

  test "users.read never authorizes users.* writes via authorize/4" do
    read_only = MapSet.new(["users.read"])

    for key <- @write_keys do
      assert {:error, :forbidden} = Authorization.authorize(read_only, key, :installation),
             "users.read authorized #{key}"
    end
  end

  test "one users write never authorizes another users write" do
    grants = MapSet.new(["users.read", "users.members.write"])

    assert {:error, :forbidden} =
             Authorization.authorize(grants, "users.admins.write", :installation)

    assert {:error, :forbidden} =
             Authorization.authorize(grants, "users.superadmins.write", :installation)
  end

  test "exact users grant authorizes its own action" do
    grants = MapSet.new(["users.read", "users.members.write"])
    assert :ok = Authorization.authorize(grants, "users.read", :installation)
    assert :ok = Authorization.authorize(grants, "users.members.write", :installation)
  end

  test "built-in grants cover all operational Console route keys" do
    operational = [
      "calls.read",
      "calls.write",
      "call_specs.read",
      "call_specs.write",
      "call_specs.use_platform_services",
      "platform_services.read",
      "platform_services.write",
      "tenant_services.read",
      "tenant_services.write",
      "tenant_api_keys.read",
      "tenant_api_keys.write",
      "tenants.read",
      "tenants.write",
      "diagnostics.read"
    ]

    for kind <- [:superadmin, :admin] do
      grants = Permission.builtin_grants(kind)

      for key <- operational do
        assert MapSet.member?(grants, key), "#{kind} grants missing #{key}"
      end
    end

    assert MapSet.member?(Permission.builtin_grants(:superadmin), "users.superadmins.write")
    assert MapSet.member?(Permission.builtin_grants(:superadmin), "users.admins.write")
  end

  test "built-in grants authorize installation operational actions exactly" do
    grants = Permission.builtin_grants(:superadmin)

    for key <- [
          "tenants.read",
          "tenants.write",
          "platform_services.read",
          "platform_services.write",
          "call_specs.use_platform_services",
          "diagnostics.read"
        ] do
      assert :ok = Authorization.authorize(grants, key, :installation), key
    end
  end

  test "built-in all-tenant context authorizes tenant operational actions" do
    grants = Permission.builtin_grants(:superadmin)

    context = %{
      assigned_tenants: %{},
      all_tenant_actions:
        MapSet.new([
          "calls.read",
          "calls.write",
          "call_specs.read",
          "call_specs.write",
          "tenant_services.read",
          "tenant_services.write",
          "tenant_api_keys.read",
          "tenant_api_keys.write"
        ])
    }

    for key <- [
          "calls.read",
          "calls.write",
          "call_specs.read",
          "call_specs.write",
          "tenant_services.read",
          "tenant_api_keys.write"
        ] do
      assert :ok = Authorization.authorize(grants, key, {:tenant, "tenant-a"}, context), key
    end
  end

  test "tenant service and API-key grants require a tenant scope and honor assignment caps" do
    for key <- ["tenant_services.read", "tenant_services.write", "tenant_api_keys.read", "tenant_api_keys.write"] do
      assert Permission.valid_scope?(key, :assigned_tenants)
      assert Permission.valid_scope?(key, :all_tenants)
      refute Permission.valid_scope?(key, :installation)

      grants = MapSet.new([key])
      context = %{assigned_tenants: %{"tenant-a" => :read_write}}
      assert :ok = Authorization.authorize(grants, key, {:tenant, "tenant-a"}, context)
      assert {:error, :forbidden} = Authorization.authorize(grants, key, {:tenant, "tenant-b"}, context)
      assert {:error, :forbidden} = Authorization.authorize(grants, key, :installation, context)
    end
  end

  defmodule StaleRoleUsers do
    @behaviour Vxpipe.Identity.Ports.Users
    @user %{
      public_id: "user-1",
      email: "user@example.com",
      normalized_email: "user@example.com",
      password_hash: "hash:correct horse 15!",
      role_public_id: "role-member",
      role_kind: :member,
      memberships: %{},
      disabled_at: nil
    }

    @impl true
    def fetch_by_email(_), do: {:error, :not_found}
    @impl true
    def fetch_by_public_id("user-1"), do: {:ok, @user}
    def fetch_by_public_id(_), do: {:error, :not_found}
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def apply_update("user-1", changes) do
      case Map.get(changes, :expected_current_role_public_id) do
        nil ->
          {:ok, Map.merge(@user, Map.drop(changes, [:expected_current_role_public_id]))}

        "role-member" ->
          {:ok, Map.merge(@user, Map.drop(changes, [:expected_current_role_public_id]))}

        _ ->
          {:error, :stale_target}
      end
    end

    def apply_update(_, _), do: {:error, :not_found}
    @impl true
    def list(_), do: {:ok, %{users: [], total: 0}}
    @impl true
    def count_enabled_superadmins, do: {:ok, 1}
  end

  defmodule MemberRoles do
    @behaviour Vxpipe.Identity.Ports.Roles
    @impl true
    def fetch("role-member"),
      do: {:ok, %{public_id: "role-member", slug: "tenant-member", kind: :member, grants: []}}

    def fetch("role-admin"),
      do: {:ok, %{public_id: "role-admin", slug: "admin", kind: :admin, grants: []}}

    def fetch(_), do: {:error, :not_found}
    @impl true
    def fetch_by_slug(_), do: {:error, :not_found}
    @impl true
    def list, do: {:ok, []}
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def apply_update(id, changes), do: {:ok, Map.put(changes, :public_id, id)}
    @impl true
    def delete(_), do: :ok
    @impl true
    def count_users(_), do: {:ok, 0}
  end

  defmodule StubSessions do
    @behaviour Vxpipe.Identity.Ports.Sessions
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def fetch_valid(_, _), do: {:error, :not_found}
    @impl true
    def revoke_one(_, _), do: :ok
    @impl true
    def revoke_for_user(_, _), do: {:ok, 1}
    @impl true
    def revoke_for_role(_, _), do: {:ok, 1}
  end

  defmodule DetailUsers do
    @behaviour Vxpipe.Identity.Ports.Users
    @user %{
      public_id: "user-1",
      email: "old@example.com",
      normalized_email: "old@example.com",
      password_hash: "hash:correct horse 15!",
      role_public_id: "role-member",
      role_kind: :member,
      memberships: %{},
      disabled_at: nil
    }

    @impl true
    def fetch_by_email(_), do: {:error, :not_found}
    @impl true
    def fetch_by_public_id("user-1"), do: {:ok, @user}
    def fetch_by_public_id(_), do: {:error, :not_found}
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def apply_update("user-1", changes) do
      case Map.get(changes, :expected_current_password_hash) do
        nil ->
          {:ok, Map.merge(@user, Map.drop(changes, [:expected_current_password_hash]))}

        "hash:correct horse 15!" ->
          {:ok, Map.merge(@user, Map.drop(changes, [:expected_current_password_hash]))}

        _ ->
          {:error, :stale_target}
      end
    end

    def apply_update(_, _), do: {:error, :not_found}
    @impl true
    def list(_), do: {:ok, %{users: [], total: 0}}
    @impl true
    def count_enabled_superadmins, do: {:ok, 1}
  end

  defp superadmin_actor do
    %{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      grants:
        MapSet.new([
          "users.read",
          "users.members.write",
          "users.admins.write",
          "users.superadmins.write"
        ]),
      account_kind: :superadmin
    }
  end

  test "update_user rejects stale role changes via expected current role" do
    deps = %{users: StaleRoleUsers, roles: MemberRoles, hasher: Vxpipe.Identity.FakeHasher}

    assert {:error, :forbidden} =
             Accounts.update_user(deps, superadmin_actor(), "user-1", %{
               email: "new@example.com",
               expected_current_role_public_id: "role-admin"
             })
  end

  test "reset_password rejects stale role changes via expected current role" do
    deps = %{
      users: StaleRoleUsers,
      roles: MemberRoles,
      hasher: Vxpipe.Identity.FakeHasher,
      sessions: Vxpipe.Identity.AuthorizationReviewTest.StubSessions
    }

    assert {:error, :forbidden} =
             Accounts.reset_password(
               deps,
               superadmin_actor(),
               "user-1",
               "another horse 15!!",
               "another horse 15!!", expected_current_role_public_id: "role-admin")
  end

  defmodule AssignedRoleUsers do
    @behaviour Vxpipe.Identity.Ports.Users
    @user %{
      public_id: "user-1",
      email: "user@example.com",
      normalized_email: "user@example.com",
      password_hash: "hash:x",
      role_public_id: "role-assigned",
      role_kind: :member,
      memberships: %{},
      disabled_at: nil
    }

    @impl true
    def fetch_by_email(_), do: {:error, :not_found}
    @impl true
    def fetch_by_public_id("user-1"), do: {:ok, @user}
    def fetch_by_public_id(_), do: {:error, :not_found}
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def apply_update("user-1", changes), do: {:ok, Map.merge(@user, changes)}
    def apply_update(_, _), do: {:error, :not_found}
    @impl true
    def list(_), do: {:ok, %{users: [], total: 0}}
    @impl true
    def count_enabled_superadmins, do: {:ok, 1}
  end

  defmodule AssignedRoles do
    @behaviour Vxpipe.Identity.Ports.Roles
    @impl true
    def fetch("role-assigned") do
      {:ok,
       %{
         public_id: "role-assigned",
         slug: "assigned",
         kind: :member,
         grants: [%{permission: "calls.read", scope: :assigned_tenants}]
       }}
    end

    def fetch(_), do: {:error, :not_found}
    @impl true
    def fetch_by_slug(_), do: {:error, :not_found}
    @impl true
    def list, do: {:ok, []}
    @impl true
    def create(attrs), do: {:ok, attrs}
    @impl true
    def apply_update(id, changes), do: {:ok, Map.put(changes, :public_id, id)}
    @impl true
    def delete(_), do: :ok
    @impl true
    def count_users(_), do: {:ok, 0}
  end

  test "assigned membership update succeeds when role unchanged" do
    deps = %{users: AssignedRoleUsers, roles: AssignedRoles, hasher: Vxpipe.Identity.FakeHasher}

    assert {:ok, _} =
             Accounts.update_user(deps, superadmin_actor(), "user-1", %{
               memberships: %{"tenant-a" => :read}
             })
  end

  test "change_own_details atomically changes email and password" do
    deps = %{
      users: Vxpipe.Identity.AuthorizationReviewTest.DetailUsers,
      hasher: Vxpipe.Identity.FakeHasher,
      sessions: Vxpipe.Identity.AuthorizationReviewTest.StubSessions,
      clock: Vxpipe.Identity.FakeClock
    }

    assert {:ok, updated} =
             Accounts.change_own_details(
               deps,
               "user-1",
               "correct horse 15!",
               "new@example.com",
               "brand new horse 15",
               "brand new horse 15"
             )

    assert updated.normalized_email == "new@example.com"
  end

  test "change_own_details rejects wrong current password without changes" do
    deps = %{
      users: Vxpipe.Identity.AuthorizationReviewTest.DetailUsers,
      hasher: Vxpipe.Identity.FakeHasher,
      sessions: Vxpipe.Identity.AuthorizationReviewTest.StubSessions,
      clock: Vxpipe.Identity.FakeClock
    }

    assert {:error, :invalid_credentials} =
             Accounts.change_own_details(
               deps,
               "user-1",
               "wrong password here!",
               "new@example.com",
               "brand new horse 15",
               "brand new horse 15"
             )
  end

  test "role update requires expected_revision" do
    deps = %{roles: Vxpipe.Identity.FakeRoles, audit: Vxpipe.Identity.Accounts.NoopAudit}

    actor = %{
      user_public_id: "11111111-1111-4111-8111-111111111111",
      session_public_id: "22222222-2222-4222-8222-222222222222",
      grants: MapSet.new(["users.read"]),
      account_kind: :superadmin
    }

    assert {:error, :stale_revision} =
             Roles.update_role(deps, actor, "role-member", %{name: "New name"})
  end

  test "role affected-user count is retrievable" do
    deps = %{roles: Vxpipe.Identity.FakeRoles}
    assert {:ok, n} = Roles.affected_user_count(deps, "role-member")
    assert is_integer(n) and n >= 0
  end
end
