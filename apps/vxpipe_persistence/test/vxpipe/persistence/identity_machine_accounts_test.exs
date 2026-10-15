defmodule Vxpipe.Persistence.IdentityMachineAccountsTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query
  alias Vxpipe.Identity.{Accounts, ApiKeyActor, Bootstrap, Roles, Sessions}

  alias Vxpipe.Persistence.{
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentityUserStore,
    IdentitySessionStore
  }

  alias Vxpipe.Persistence.Schema.{ApiKey, IdentityUser, Tenant, UserAccessEvent}

  setup do
    result =
      case Bootstrap.status(deps()) do
        {:ok, :pending_first_run} ->
          Bootstrap.complete_first_run(
            deps(),
            "machine-root@example.test",
            password(),
            password()
          )

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

          Bootstrap.complete_with_proof(
            deps(),
            proof,
            "machine-root@example.test",
            password(),
            password()
          )
      end

    {:ok, %{user: root}} = result

    key = insert_key(nil, ["platform"])
    {:ok, actor} = ApiKeyActor.new(key.public_id)
    %{actor: actor, key: key, root: root}
  end

  test "platform account writes retain key audit attribution and privileged target guards", %{
    actor: actor,
    key: key,
    root: root
  } do
    for kind <- ["tenant-manager", "admin", "superadmin"] do
      {:ok, role} = IdentityRoleStore.fetch_by_slug(kind)

      assert {:ok, user} =
               Accounts.create_user(deps(), actor, attrs(role.public_id, kind <> "@example.test"))

      refute Map.has_key?(user, :password_hash)
      stored = Repo.get_by!(IdentityUser, public_id: user.public_id)

      event =
        Repo.one!(
          from(e in UserAccessEvent,
            where: e.target_user_id == ^stored.id and e.action == "user_created"
          )
        )

      assert event.actor_api_key_id == key.id
      assert event.actor_user_id == nil
      refute inspect(event.summary) =~ password()
    end

    assert {:ok, _} = Accounts.update_user(deps(), actor, root.public_id, %{disabled: true})

    {:ok, %{users: users}} =
      Accounts.list_users(deps(), actor, %{search: "superadmin@example.test"})

    [last] = users

    assert {:error, :last_superadmin} =
             Accounts.update_user(deps(), actor, last.public_id, %{disabled: true})
  end

  test "revoked and tenant keys cannot pass transaction-time account revalidation", %{
    actor: actor,
    key: key,
    root: root
  } do
    {:ok, role} = IdentityRoleStore.fetch_by_slug("tenant-manager")

    Repo.update_all(from(k in ApiKey, where: k.id == ^key.id),
      set: [revoked_at: DateTime.utc_now()]
    )

    assert {:error, :forbidden} =
             Accounts.create_user(deps(), actor, attrs(role.public_id, "revoked@example.test"))

    assert {:error, :forbidden} =
             Accounts.update_user(deps(), actor, root.public_id, %{email: "forged@example.test"})

    refute Repo.get_by(IdentityUser, normalized_email: "revoked@example.test")

    tenant =
      Repo.insert!(Tenant.changeset(%Tenant{}, %{key: "AAAAAAAAAAAAAAAA", name: "Assigned"}))

    tenant_key = insert_key(tenant.id, ["admin", "calls"])
    {:ok, forged} = ApiKeyActor.new(tenant_key.public_id)

    assert {:error, :forbidden} =
             Accounts.create_user(
               deps(),
               forged,
               attrs(role.public_id, "tenant-forged@example.test")
             )
  end

  test "partial updates disable and reactivate without reviving sessions or clearing memberships",
       %{actor: actor} do
    tenant =
      Repo.insert!(Tenant.changeset(%Tenant{}, %{key: "AAAAAAAAAAAAAAAA", name: "Assigned"}))

    {:ok, role} = IdentityRoleStore.fetch_by_slug("tenant-manager")

    assert {:ok, user} =
             Accounts.create_user(
               deps(),
               actor,
               Map.put(attrs(role.public_id, "member@example.test"), :memberships, %{
                 tenant.key => :read_write
               })
             )

    {:ok, %{token: token}} = Sessions.login(deps(), user.email, password(), "local")
    assert {:ok, _} = Sessions.authenticate(deps(), token)

    assert {:ok, disabled} =
             Accounts.update_user(deps(), actor, user.public_id, %{disabled: true})

    assert disabled.disabled_at
    assert disabled.memberships == %{tenant.key => :read_write}
    assert {:error, _} = Sessions.authenticate(deps(), token)

    assert {:ok, changed} =
             Accounts.update_user(deps(), actor, user.public_id, %{email: "changed@example.test"})

    assert changed.disabled_at
    assert changed.memberships == disabled.memberships
    assert changed.role_public_id == role.public_id

    assert {:ok, enabled} =
             Accounts.update_user(deps(), actor, user.public_id, %{disabled: false})

    assert enabled.disabled_at == nil
    assert {:error, _} = Sessions.authenticate(deps(), token)
    assert {:ok, _} = Sessions.login(deps(), enabled.email, password(), "local")
  end

  test "safe user and role-option pages are bounded and omit grants and secrets", %{actor: actor} do
    assert {:ok, %{roles: roles, total: total, page_size: 1}} =
             Roles.list_role_options(deps(), actor, %{page_size: 1})

    assert length(roles) == 1
    assert total >= 4
    refute Map.has_key?(hd(roles), :grants)

    assert {:error, :page_out_of_range} =
             Roles.list_role_options(deps(), actor, %{page: total + 1, page_size: 1})

    assert {:ok, %{users: [_], total: 1}} =
             Accounts.list_users(deps(), actor, %{search: "machine-root"})

    assert {:error, :invalid_search} =
             Accounts.list_users(deps(), actor, %{search: String.duplicate("x", 121)})
  end

  defp insert_key(tenant_id, scopes) do
    Repo.insert!(
      ApiKey.changeset(%ApiKey{}, %{
        public_id: Ecto.UUID.generate(),
        name: "synthetic",
        tenant_id: tenant_id,
        scopes: scopes,
        digest: :crypto.strong_rand_bytes(32)
      })
    )
  end

  defp attrs(role, email),
    do: %{
      email: email,
      role_public_id: role,
      memberships: %{},
      password: password(),
      password_confirmation: password()
    }

  defp password, do: "correct horse 15!"

  defp deps do
    %{
      users: IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: IdentityAuditStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }
  end
end
