defmodule Vxpipe.Persistence.IdentityAuthReviewTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.{
    IdentityAttemptStore,
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore
  }

  alias Vxpipe.Persistence.Repo
  alias Vxpipe.Persistence.Schema.Tenant

  defp deps do
    %{
      users: IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: IdentityAuditStore,
      attempts: IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher,
      tokens: Vxpipe.Identity.Tokens,
      clock: Vxpipe.Identity.Clock,
      uuid: Vxpipe.Identity.Uuid
    }
  end

  defp real_actor!(email \\ "root@example.com", password \\ "correct horse 15!") do
    {:ok, %{token: token}} =
      Vxpipe.Identity.Sessions.login(deps(), email, password, "127.0.0.1")

    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(deps(), token)
    Map.from_struct(principal)
  end

  defp setup_superadmin(email \\ "root@example.com") do
    params = deps()

    case Vxpipe.Identity.Bootstrap.status(params) do
      {:ok, :pending_first_run} ->
        Vxpipe.Identity.Bootstrap.complete_first_run(
          params,
          email,
          "correct horse 15!",
          "correct horse 15!"
        )

      {:ok, :pending_operator_proof} ->
        {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

        Vxpipe.Identity.Bootstrap.complete_with_proof(
          params,
          proof,
          email,
          "correct horse 15!",
          "correct horse 15!"
        )
    end
  end

  defp member_role! do
    {:ok, roles} = IdentityRoleStore.list()
    Enum.find(roles, &(&1.slug == "tenant-member"))
  end

  defp create_tenant!(key) do
    %Tenant{}
    |> Tenant.changeset(%{key: key, name: "Tenant #{key}"})
    |> Repo.insert!()
  end

  test "user update rejects stale expected role" do
    {:ok, %{user: root}} = setup_superadmin()
    member = member_role!()
    actor = real_actor!()

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.update_user(deps(), actor, root.public_id, %{
               email: "new@example.com",
               expected_current_role_public_id: member.public_id
             })
  end

  test "user update rejects stale expected password hash" do
    {:ok, %{user: root}} = setup_superadmin()

    assert {:error, :stale_target} =
             IdentityUserStore.apply_update(root.public_id, %{
               email: "new@example.com",
               expected_current_password_hash: "bogus-hash"
             })
  end

  test "store-level user update revokes sessions atomically" do
    {:ok, %{token: token, user: root}} = setup_superadmin()
    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)
    member = member_role!()
    actor = real_actor!()

    {:ok, roles} = IdentityRoleStore.list()
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(deps(), actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    assert {:ok, _} =
             IdentityUserStore.apply_update(root.public_id, %{
               role_public_id: member.public_id,
               expected_current_role_public_id: root.role_public_id,
               actor_user_public_id: actor.user_public_id,
               actor_session_public_id: actor.session_public_id
             })

    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)
  end

  test "store-level password update revokes sessions atomically" do
    {:ok, %{token: token, user: root}} = setup_superadmin()
    {:ok, hash} = Vxpipe.Identity.Argon2Hasher.hash("another horse 15!!")
    {:ok, stored} = IdentityUserStore.fetch_by_public_id(root.public_id)

    assert {:ok, _} =
             IdentityUserStore.apply_update(root.public_id, %{
               password_hash: hash,
               expected_current_password_hash: stored.password_hash
             })

    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "root@example.com",
               "another horse 15!!",
               "127.0.0.1"
             )
  end

  test "assigned membership update succeeds when role unchanged" do
    {:ok, _} = setup_superadmin()
    params = Map.put(deps(), :clock, Vxpipe.Identity.Clock)
    actor = real_actor!()
    member = member_role!()
    create_tenant!("testtenant000001")

    {:ok, user} =
      Vxpipe.Identity.Accounts.create_user(params, actor, %{
        email: "member@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: member.public_id,
        memberships: %{"testtenant000001" => :read}
      })

    assert {:ok, updated} =
             Vxpipe.Identity.Accounts.update_user(params, actor, user.public_id, %{
               memberships: %{"testtenant000001" => :read_write}
             })

    assert updated.memberships == %{"testtenant000001" => :read_write}
  end

  test "change_own_details changes email and password atomically" do
    {:ok, %{token: token, user: root}} = setup_superadmin()

    assert {:ok, updated} =
             Vxpipe.Identity.Accounts.change_own_details(
               deps(),
               root.public_id,
               "correct horse 15!",
               "renamed@example.com",
               "brand new horse 15",
               "brand new horse 15"
             )

    assert updated.normalized_email == "renamed@example.com"
    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "renamed@example.com",
               "brand new horse 15",
               "127.0.0.1"
             )
  end

  test "change_own_details rejects wrong current password without changes" do
    {:ok, %{token: token, user: root}} = setup_superadmin()

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Accounts.change_own_details(
               deps(),
               root.public_id,
               "wrong password here!",
               "renamed@example.com",
               "brand new horse 15",
               "brand new horse 15"
             )

    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "root@example.com",
               "correct horse 15!",
               "127.0.0.1"
             )
  end

  test "role update without expected revision is rejected" do
    {:ok, _} = setup_superadmin()
    actor = real_actor!()

    {:ok, role} =
      Vxpipe.Identity.Roles.create_role(deps(), actor, %{
        name: "Callers",
        slug: "callers-rev",
        grants: [%{permission: "calls.read", scope: :assigned_tenants}]
      })

    assert {:error, :stale_revision} =
             IdentityRoleStore.apply_update(role.public_id, %{name: "Renamed"})

    assert {:error, :stale_revision} =
             Vxpipe.Identity.Roles.update_role(deps(), actor, role.public_id, %{
               name: "Renamed"
             })

    assert {:ok, updated} =
             Vxpipe.Identity.Roles.update_role(deps(), actor, role.public_id, %{
               name: "Renamed",
               expected_revision: role.revision
             })

    assert updated.revision == role.revision + 1
  end

  test "role affected-user count reflects assignments" do
    {:ok, _} = setup_superadmin()
    member = member_role!()
    actor = real_actor!()

    assert {:ok, 0} = IdentityRoleStore.count_users(member.public_id)
    assert {:ok, 0} = Vxpipe.Identity.Roles.affected_user_count(deps(), member.public_id)

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(deps(), actor, %{
        email: "member@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: member.public_id,
        memberships: %{}
      })

    assert {:ok, 1} = IdentityRoleStore.count_users(member.public_id)
    assert {:ok, 1} = Vxpipe.Identity.Roles.affected_user_count(deps(), member.public_id)
  end

  test "role definition change revokes member sessions atomically" do
    {:ok, _} = setup_superadmin()
    params = deps()
    actor = real_actor!()

    {:ok, role} =
      Vxpipe.Identity.Roles.create_role(params, actor, %{
        name: "Callers",
        slug: "callers-revoke",
        grants: [
          %{permission: "calls.read", scope: :assigned_tenants},
          %{permission: "calls.write", scope: :assigned_tenants}
        ]
      })

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(params, actor, %{
        email: "member@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: role.public_id,
        memberships: %{}
      })

    {:ok, %{token: token}} =
      Vxpipe.Identity.Sessions.login(
        params,
        "member@example.com",
        "correct horse 15!",
        "127.0.0.1"
      )

    assert {:ok, updated} =
             Vxpipe.Identity.Roles.update_role(params, actor, role.public_id, %{
               name: "Callers v2",
               grants: [%{permission: "calls.read", scope: :assigned_tenants}],
               expected_revision: role.revision
             })

    assert updated.revision == role.revision + 1
    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(params, token)
  end

  test "seeded roles are exactly four with Tenant Manager operational grants" do
    {:ok, roles} = IdentityRoleStore.list()
    by_slug = Map.new(roles, &{&1.slug, &1})

    assert Map.has_key?(by_slug, "superadmin")
    assert Map.has_key?(by_slug, "admin")
    assert Map.has_key?(by_slug, "tenant-manager")
    assert Map.has_key?(by_slug, "tenant-member")
    refute Map.has_key?(by_slug, "platform-manager")
    refute Map.has_key?(by_slug, "call-reviewer")
    refute Map.has_key?(by_slug, "directory-reader")

    manager_grants =
      MapSet.new(by_slug["tenant-manager"].grants, &{&1.permission, &1.scope})

    assert manager_grants ==
             MapSet.new([
               {"calls.read", :assigned_tenants},
               {"calls.write", :assigned_tenants},
               {"call_specs.read", :assigned_tenants},
               {"call_specs.write", :assigned_tenants},
               {"tenant_services.read", :assigned_tenants},
               {"tenant_services.write", :assigned_tenants},
               {"tenant_api_keys.read", :assigned_tenants},
               {"tenant_api_keys.write", :assigned_tenants},
               {"call_specs.use_platform_services", :installation}
             ])

    member_grants = MapSet.new(by_slug["tenant-member"].grants, &{&1.permission, &1.scope})

    assert member_grants ==
             MapSet.new([
               {"calls.read", :assigned_tenants},
               {"call_specs.read", :assigned_tenants}
             ])

    for role <- [by_slug["tenant-manager"], by_slug["tenant-member"]] do
      refute Enum.any?(role.grants, fn %{permission: p} -> String.starts_with?(p, "users.") end)

      refute Enum.any?(role.grants, fn %{permission: p} -> String.starts_with?(p, "platform_") end)
    end

    superadmin = by_slug["superadmin"]
    assert superadmin.kind == :superadmin

    assert MapSet.new(superadmin.grants, & &1.permission) ==
             Vxpipe.Identity.Permission.builtin_grants(:superadmin)
  end

  test "role change without expected current role fails closed" do
    {:ok, %{user: root}} = setup_superadmin()
    member = member_role!()

    assert {:error, :stale_target} =
             IdentityUserStore.apply_update(root.public_id, %{
               role_public_id: member.public_id
             })
  end

  test "concurrent demotion closes the write gap via revalidation" do
    {:ok, %{token: token, user: first}} = setup_superadmin()
    params = deps()
    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(params, token)
    first_actor = Map.from_struct(principal)

    {:ok, roles} = IdentityRoleStore.list()
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))
    member_role = Enum.find(roles, &(&1.slug == "tenant-member"))

    # Second superadmin so demoting the first is allowed.
    {:ok, second} =
      Vxpipe.Identity.Accounts.create_user(params, first_actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    {:ok, second_principal} =
      Vxpipe.Identity.Sessions.login(
        params,
        "second@example.com",
        "correct horse 15!",
        "127.0.0.1"
      )
      |> case do
        {:ok, %{token: t}} -> Vxpipe.Identity.Sessions.authenticate(params, t)
        error -> error
      end

    second_actor = Map.from_struct(second_principal)

    # Concurrently demote the first actor via the still-privileged second actor
    # (simulates a race between auth check and write commit).
    assert {:ok, _} =
             Vxpipe.Identity.Accounts.update_user(params, second_actor, first.public_id, %{
               role_public_id: member_role.public_id
             })

    # Stale principal still carries superadmin grants, but the store revalidates
    # the actor inside the write transaction and must deny.
    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.create_user(params, principal, %{
               email: "race@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member_role.public_id,
               memberships: %{}
             })

    # Sanity: the second (still privileged) actor can create.
    assert {:ok, _} =
             Vxpipe.Identity.Accounts.create_user(params, second_principal, %{
               email: "race2@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member_role.public_id,
               memberships: %{}
             })

    assert second.public_id != nil
  end

  test "revoked session closes the write gap via revalidation" do
    {:ok, %{token: token}} = setup_superadmin()
    params = deps()
    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(params, token)
    member = member_role!()

    :ok = Vxpipe.Identity.Sessions.logout(params, token)

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.create_user(params, principal, %{
               email: "revoked@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member.public_id,
               memberships: %{}
             })
  end

  test "disabled actor closes the write gap via revalidation" do
    {:ok, %{token: token, user: first}} = setup_superadmin()
    params = deps()
    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(params, token)
    first_actor = Map.from_struct(principal)

    {:ok, roles} = IdentityRoleStore.list()
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(params, first_actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    # Disable the actor directly (second superadmin keeps the operation allowed).
    {:ok, second_principal} =
      Vxpipe.Identity.Sessions.login(
        params,
        "second@example.com",
        "correct horse 15!",
        "127.0.0.1"
      )
      |> case do
        {:ok, %{token: t}} -> Vxpipe.Identity.Sessions.authenticate(params, t)
        error -> error
      end

    assert {:ok, _} =
             Vxpipe.Identity.Accounts.update_user(params, second_principal, first.public_id, %{
               disabled: true
             })

    member = member_role!()

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.create_user(params, principal, %{
               email: "disabled-race@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member.public_id,
               memberships: %{}
             })
  end

  test "local recovery proof resets credentials and revokes sessions atomically" do
    {:ok, %{token: token, user: root}} = setup_superadmin()
    params = deps()
    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(params, token)

    assert {:ok, %{proof: proof}} = IdentityInstallationStore.issue_recovery_proof(900)

    assert {:ok, %{token: new_token, user: recovered}} =
             Vxpipe.Identity.Bootstrap.recover_with_proof(
               params,
               proof,
               "root@example.com",
               "recovered horse 15!!",
               "recovered horse 15!!"
             )

    assert recovered.public_id == root.public_id
    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(params, token)
    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(params, new_token)

    # Proof is single-use.
    assert {:error, :invalid_proof} =
             Vxpipe.Identity.Bootstrap.recover_with_proof(
               params,
               proof,
               "root@example.com",
               "another horse 15!!",
               "another horse 15!!"
             )

    # New password works, old does not.
    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               params,
               "root@example.com",
               "recovered horse 15!!",
               "127.0.0.1"
             )

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Sessions.login(
               params,
               "root@example.com",
               "correct horse 15!",
               "127.0.0.1"
             )
  end

  test "recovery rejects non-superadmin targets and requires completion" do
    {:ok, _} = setup_superadmin()
    params = deps()
    member = member_role!()
    actor = real_actor!()

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(params, actor, %{
        email: "member@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: member.public_id,
        memberships: %{}
      })

    assert {:ok, %{proof: proof}} = IdentityInstallationStore.issue_recovery_proof(900)

    assert {:error, :not_found} =
             Vxpipe.Identity.Bootstrap.recover_with_proof(
               params,
               proof,
               "member@example.com",
               "recovered horse 15!!",
               "recovered horse 15!!"
             )
  end
end
