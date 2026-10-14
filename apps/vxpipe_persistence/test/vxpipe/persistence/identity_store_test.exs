defmodule Vxpipe.Persistence.IdentityStoreTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.{
    IdentityAttemptStore,
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore
  }

  test "roles no longer store or expose a description" do
    result = Vxpipe.Persistence.Repo.query!("SELECT column_name FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'roles' AND column_name = 'description'")
    assert result.rows == []
    assert {:ok, roles} = IdentityRoleStore.list()
    assert roles != []
    refute Enum.any?(roles, &Map.has_key?(&1, :description))
  end

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

  test "seeded Tenant Manager has assigned service and API-key grants" do
    {:ok, manager} = IdentityRoleStore.fetch_by_slug("tenant-manager")
    {:ok, member} = IdentityRoleStore.fetch_by_slug("tenant-member")

    for key <- ["tenant_services.read", "tenant_services.write", "tenant_api_keys.write"] do
      assert %{permission: ^key, scope: :assigned_tenants} =
               Enum.find(manager.grants, &(&1.permission == key))

      refute Enum.any?(member.grants, &(&1.permission == key))
    end

    assert %{permission: "platform_services.read", scope: :installation} =
             Enum.find(manager.grants, &(&1.permission == "platform_services.read"))
  end

  test "setup completes singleton and logs in the initial superadmin" do
    assert {:ok, status} = Vxpipe.Identity.Bootstrap.status(deps())
    assert status in [:pending_first_run, :pending_operator_proof]

    assert {:ok, %{token: token, user: user}} = setup_superadmin()

    assert is_binary(token)
    assert user.normalized_email == "root@example.com"
    refute Map.has_key?(user, :password_hash)

    assert {:ok, :complete} = Vxpipe.Identity.Bootstrap.status(deps())

    assert {:error, :already_completed} =
             Vxpipe.Identity.Bootstrap.complete_first_run(
               deps(),
               "other@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )

    assert {:ok, %Vxpipe.Identity.Principal{account_kind: :superadmin}} =
             Vxpipe.Identity.Sessions.authenticate(deps(), token)
  end

  test "anonymous first-run claim is rejected on an upgraded database" do
    assert {:ok, status} = Vxpipe.Identity.Bootstrap.status(deps())

    case status do
      :pending_operator_proof ->
        assert {:error, :proof_required} =
                 Vxpipe.Identity.Bootstrap.complete_first_run(
                   deps(),
                   "root@example.com",
                   "correct horse 15!",
                   "correct horse 15!"
                 )

        assert {:error, :invalid_proof} =
                 Vxpipe.Identity.Bootstrap.complete_with_proof(
                   deps(),
                   "bogus-proof",
                   "root@example.com",
                   "correct horse 15!",
                   "correct horse 15!"
                 )

      :pending_first_run ->
        assert {:ok, _} = setup_superadmin()
    end
  end

  test "login uses generic failures, logout revokes, replay is denied" do
    {:ok, %{token: token}} = setup_superadmin()

    :ok = Vxpipe.Identity.Sessions.logout(deps(), token)
    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "root@example.com",
               "wrong password here!",
               "127.0.0.1"
             )

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "missing@example.com",
               "correct horse 15!",
               "127.0.0.1"
             )

    assert {:ok, %{token: token2}} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "  ROOT@example.com ",
               "correct horse 15!",
               "127.0.0.1"
             )

    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token2)
  end

  test "last enabled superadmin cannot be disabled" do
    {:ok, %{user: first}} = setup_superadmin()
    actor = real_actor!()

    assert {:error, :last_superadmin} =
             Vxpipe.Identity.Accounts.update_user(deps(), actor, first.public_id, %{
               disabled: true
             })

    {:ok, roles} = IdentityRoleStore.list()
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))

    {:ok, second} =
      Vxpipe.Identity.Accounts.create_user(deps(), actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    assert {:ok, _} =
             Vxpipe.Identity.Accounts.update_user(deps(), actor, first.public_id, %{
               disabled: true
             })

    second_actor = real_actor!("second@example.com")

    assert {:error, :last_superadmin} =
             Vxpipe.Identity.Accounts.update_user(deps(), second_actor, second.public_id, %{
               disabled: true
             })
  end

  test "ordinary role CRUD rejects reserved grants and protects built-ins" do
    {:ok, _} = setup_superadmin()
    actor = real_actor!()

    assert {:error, :reserved_permission} =
             Vxpipe.Identity.Roles.create_role(deps(), actor, %{
               name: "Sneaky",
               slug: "sneaky",
               grants: [%{permission: "users.members.write", scope: :installation}]
             })

    {:ok, roles} = IdentityRoleStore.list()
    builtin = Enum.find(roles, &(&1.kind == :superadmin))

    assert {:error, :protected_role} =
             Vxpipe.Identity.Roles.delete_role(deps(), actor, builtin.public_id)

    assert {:ok, role} =
             Vxpipe.Identity.Roles.create_role(deps(), actor, %{
               name: "Callers",
               slug: "callers",
               grants: [
                 %{permission: "calls.read", scope: :assigned_tenants},
                 %{permission: "calls.write", scope: :assigned_tenants}
               ]
             })

    {:ok, _user} =
      Vxpipe.Identity.Accounts.create_user(deps(), actor, %{
        email: "caller@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: role.public_id,
        memberships: %{}
      })

    assert {:error, :role_in_use} =
             Vxpipe.Identity.Roles.delete_role(deps(), actor, role.public_id)
  end

  test "admin cannot reset a superadmin password; superadmin can" do
    {:ok, %{user: root}} = setup_superadmin()
    super_actor = real_actor!()

    {:ok, roles} = IdentityRoleStore.list()
    admin_role = Enum.find(roles, &(&1.kind == :admin))

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(deps(), super_actor, %{
        email: "admin@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: admin_role.public_id,
        memberships: %{}
      })

    admin_actor = real_actor!("admin@example.com")

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.reset_password(
               deps(),
               admin_actor,
               root.public_id,
               "another horse 15!!",
               "another horse 15!!"
             )

    assert :ok =
             Vxpipe.Identity.Accounts.reset_password(
               deps(),
               super_actor,
               root.public_id,
               "another horse 15!!",
               "another horse 15!!"
             )

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "root@example.com",
               "another horse 15!!",
               "127.0.0.1"
             )
  end

  test "audit events never carry secrets" do
    {:ok, %{user: _}} = setup_superadmin()

    events = IdentityAuditStore.recent_events(50)
    assert length(events) >= 1

    for event <- events do
      refute Map.has_key?(event.summary || %{}, :password_hash)
      refute Map.has_key?(event.summary || %{}, "password_hash")
    end
  end
end
