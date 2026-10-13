defmodule Vxpipe.Persistence.IdentityWorkflowsTest do
  use Vxpipe.Persistence.DataCase, async: false

  alias Vxpipe.Persistence.{
    IdentityAttemptStore,
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore
  }

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

  test "concurrent setup submissions produce exactly one initial superadmin" do
    assert {:ok, status} = Vxpipe.Identity.Bootstrap.status(deps())

    if status == :pending_operator_proof do
      {:ok, %{proof: proof_a}} = IdentityInstallationStore.issue_setup_proof(900)
      {:ok, %{proof: proof_b}} = IdentityInstallationStore.issue_setup_proof(900)
      params = deps()

      tasks =
        for {proof, email} <- [{proof_a, "a@example.com"}, {proof_b, "b@example.com"}] do
          Task.async(fn ->
            Vxpipe.Identity.Bootstrap.complete_with_proof(
              params,
              proof,
              email,
              "correct horse 15!",
              "correct horse 15!"
            )
          end)
        end

      results = Task.await_many(tasks, 15_000)
      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :already_completed}, &1)) == 1
      assert {:ok, :complete} = Vxpipe.Identity.Bootstrap.status(params)
    else
      assert {:ok, _} = setup_superadmin()
    end
  end

  test "bounded login throttling trips without permanent lockout" do
    {:ok, _} = setup_superadmin()
    params = deps()
    now = DateTime.utc_now()

    for _ <- 1..10 do
      :ok = IdentityAttemptStore.record("root@example.com", "10.0.0.9", now)
    end

    assert {:error, :rate_limited} =
             Vxpipe.Identity.Sessions.login(
               params,
               "root@example.com",
               "correct horse 15!",
               "10.0.0.9"
             )

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Sessions.login(
               params,
               "other@example.com",
               "correct horse 15!",
               "10.0.0.10"
             )
  end

  test "bounded setup throttling trips and records proof failures" do
    params = deps()
    now = DateTime.utc_now()

    for _ <- 1..10 do
      :ok = IdentityAttemptStore.record("root@example.com", "local", now)
    end

    assert {:error, :rate_limited} =
             Vxpipe.Identity.Bootstrap.complete_first_run(
               params,
               "root@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )

    # Different account is not throttled; invalid proof is recorded for throttling.
    assert {:error, _} =
             Vxpipe.Identity.Bootstrap.complete_with_proof(
               params,
               "bogus-proof",
               "other@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )

    assert {:ok, %{account: attempts, address: _}} =
             IdentityAttemptStore.recent(
               "other@example.com",
               "local",
               DateTime.utc_now(),
               600
             )

    assert length(attempts) >= 1
  end

  test "expired sessions are rejected" do
    {:ok, %{user: user}} = setup_superadmin()
    digest = String.duplicate("e", 64)
    past = DateTime.add(DateTime.utc_now(), -3600, :second)

    {:ok, _} =
      IdentitySessionStore.create(%{
        public_id: Vxpipe.Identity.Uuid.generate(),
        user_public_id: user.public_id,
        digest: digest,
        expires_at: past
      })

    assert {:error, :expired} = IdentitySessionStore.fetch_valid(digest, DateTime.utc_now())
  end

  test "administrative reset revokes target sessions and replaces the hash atomically" do
    {:ok, %{token: token, user: root}} = setup_superadmin()

    assert {:ok, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)
    actor = real_actor!()

    assert :ok =
             Vxpipe.Identity.Accounts.reset_password(
               deps(),
               actor,
               root.public_id,
               "another horse 15!!",
               "another horse 15!!"
             )

    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(deps(), token)

    refreshed = real_actor!("root@example.com", "another horse 15!!")

    assert {:error, :confirmation_mismatch} =
             Vxpipe.Identity.Accounts.reset_password(
               deps(),
               refreshed,
               root.public_id,
               "another horse 15!!",
               "mismatch horse 15!!"
             )

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               deps(),
               "root@example.com",
               "another horse 15!!",
               "127.0.0.1"
             )
  end

  test "self-service password change requires the current password and revokes sessions" do
    {:ok, %{token: token, user: root}} = setup_superadmin()
    params = deps()

    assert {:error, :invalid_credentials} =
             Vxpipe.Identity.Accounts.change_own_password(
               params,
               root.public_id,
               "wrong current pw!!",
               "brand new horse 15",
               "brand new horse 15"
             )

    assert :ok =
             Vxpipe.Identity.Accounts.change_own_password(
               params,
               root.public_id,
               "correct horse 15!",
               "brand new horse 15",
               "brand new horse 15"
             )

    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(params, token)

    assert {:ok, _} =
             Vxpipe.Identity.Sessions.login(
               params,
               "root@example.com",
               "brand new horse 15",
               "127.0.0.1"
             )
  end

  test "self-service email change normalizes and keeps the role" do
    {:ok, %{user: root}} = setup_superadmin()

    assert {:ok, updated} =
             Vxpipe.Identity.Accounts.change_own_email(
               deps(),
               root.public_id,
               "correct horse 15!",
               "  Root2@Example.com "
             )

    assert updated.normalized_email == "root2@example.com"
    assert updated.role_kind == :superadmin
  end

  test "directory search and role filters apply server-side before pagination" do
    {:ok, %{user: _root}} = setup_superadmin()
    params = deps()
    actor = real_actor!()

    {:ok, roles} = IdentityRoleStore.list()
    member_role = Enum.find(roles, &(&1.slug == "tenant-member"))

    for email <- ["alice@example.com", "bob@example.com", "carol@example.com"] do
      {:ok, _} =
        Vxpipe.Identity.Accounts.create_user(params, actor, %{
          email: email,
          password: "correct horse 15!",
          password_confirmation: "correct horse 15!",
          role_public_id: member_role.public_id,
          memberships: %{}
        })
    end

    assert {:ok, %{users: [_], total: 1}} =
             Vxpipe.Identity.Accounts.list_users(params, actor, %{search: "ALICE"})

    assert {:ok, %{users: users, total: 3}} =
             Vxpipe.Identity.Accounts.list_users(params, actor, %{
               role_public_id: member_role.public_id
             })

    assert length(users) == 3

    assert {:error, :invalid_role_filter} =
             Vxpipe.Identity.Accounts.list_users(params, actor, %{role_public_id: "not-a-uuid"})

    assert {:error, :invalid_role_filter} =
             Vxpipe.Identity.Accounts.list_users(params, actor, %{
               role_public_id: Ecto.UUID.generate()
             })

    assert {:ok, %{users: page, total: 4}} =
             Vxpipe.Identity.Accounts.list_users(params, actor, %{page: 1, page_size: 2})

    assert length(page) == 2
  end

  test "demoting the last enabled superadmin is rejected; role edits revoke sessions" do
    {:ok, %{token: token, user: first}} = setup_superadmin()
    params = deps()
    actor = real_actor!()

    {:ok, roles} = IdentityRoleStore.list()
    member_role = Enum.find(roles, &(&1.slug == "tenant-member"))
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))

    assert {:error, :last_superadmin} =
             Vxpipe.Identity.Accounts.update_user(params, actor, first.public_id, %{
               role_public_id: member_role.public_id
             })

    {:ok, second} =
      Vxpipe.Identity.Accounts.create_user(params, actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    assert {:ok, _} =
             Vxpipe.Identity.Accounts.update_user(params, actor, first.public_id, %{
               role_public_id: member_role.public_id
             })

    assert {:error, _} = Vxpipe.Identity.Sessions.authenticate(params, token)

    second_actor = real_actor!("second@example.com")

    assert {:error, :last_superadmin} =
             Vxpipe.Identity.Accounts.update_user(params, second_actor, second.public_id, %{
               role_public_id: member_role.public_id
             })
  end

  test "disabled accounts cannot authenticate" do
    {:ok, %{user: first}} = setup_superadmin()
    params = deps()
    actor = real_actor!()

    {:ok, roles} = IdentityRoleStore.list()
    superadmin_role = Enum.find(roles, &(&1.kind == :superadmin))

    {:ok, _} =
      Vxpipe.Identity.Accounts.create_user(params, actor, %{
        email: "second@example.com",
        password: "correct horse 15!",
        password_confirmation: "correct horse 15!",
        role_public_id: superadmin_role.public_id,
        memberships: %{}
      })

    {:ok, _} =
      Vxpipe.Identity.Accounts.update_user(params, actor, first.public_id, %{disabled: true})

    assert {:error, :disabled} =
             Vxpipe.Identity.Sessions.login(
               params,
               "root@example.com",
               "correct horse 15!",
               "127.0.0.1"
             )
  end
end
