defmodule Vxpipe.Persistence.IdentityFinalReviewTest do
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
  alias Vxpipe.Persistence.Schema.AuthenticationInstallation

  defp deps(audit \\ IdentityAuditStore) do
    %{
      users: IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: audit,
      attempts: IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher,
      tokens: Vxpipe.Identity.Tokens,
      clock: Vxpipe.Identity.Clock,
      uuid: Vxpipe.Identity.Uuid
    }
  end

  defmodule FailingAudit do
    @behaviour Vxpipe.Identity.Ports.Audit
    @impl true
    def append(_), do: {:error, :unavailable}
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

  test "privileged user create rejects missing actor through public workflow" do
    _ = setup_superadmin()
    member = member_role!()

    forged = %{
      user_public_id: nil,
      grants:
        MapSet.new([
          "users.read",
          "users.members.write",
          "users.admins.write",
          "users.superadmins.write"
        ]),
      account_kind: :superadmin
    }

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.create_user(deps(), forged, %{
               email: "forged@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member.public_id,
               memberships: %{}
             })
  end

  test "privileged user create rejects placeholder actor and missing session at store boundary" do
    {:ok, %{user: _}} = setup_superadmin()
    member = member_role!()

    assert {:error, :forbidden} =
             IdentityUserStore.create(%{
               public_id: Ecto.UUID.generate(),
               email: "x@example.com",
               normalized_email: "x@example.com",
               password_hash: "hash",
               role_public_id: member.public_id,
               memberships: %{},
               actor_user_public_id: "setup"
             })

    assert {:error, :forbidden} =
             IdentityUserStore.create(%{
               public_id: Ecto.UUID.generate(),
               email: "y@example.com",
               normalized_email: "y@example.com",
               password_hash: "hash",
               role_public_id: member.public_id,
               memberships: %{},
               actor_user_public_id: Ecto.UUID.generate(),
               actor_session_public_id: "not-a-uuid"
             })
  end

  test "privileged role create rejects forged actor at store boundary" do
    _ = setup_superadmin()

    assert {:error, :forbidden} =
             IdentityRoleStore.create(%{
               slug: "forged-role",
               name: "Forged",
               grants: [],
               actor_user_public_id: Ecto.UUID.generate()
             })
  end

  test "live session is required: revoked session cannot write" do
    {:ok, %{token: token}} = setup_superadmin()
    params = deps()
    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(params, token)
    member = member_role!()
    :ok = Vxpipe.Identity.Sessions.logout(params, token)

    assert {:error, :forbidden} =
             Vxpipe.Identity.Accounts.create_user(params, Map.from_struct(principal), %{
               email: "revoked-write@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: member.public_id,
               memberships: %{}
             })
  end

  test "setup reports success even when outer audit sink fails (no false failure) with durable audit" do
    count_before = length(IdentityAuditStore.recent_events(100))
    failing_deps = Map.put(deps(), :audit, FailingAudit)

    result =
      case Vxpipe.Identity.Bootstrap.status(failing_deps) do
        {:ok, :pending_first_run} ->
          Vxpipe.Identity.Bootstrap.complete_first_run(
            failing_deps,
            "root@example.com",
            "correct horse 15!",
            "correct horse 15!"
          )

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

          Vxpipe.Identity.Bootstrap.complete_with_proof(
            failing_deps,
            proof,
            "root@example.com",
            "correct horse 15!",
            "correct horse 15!"
          )
      end

    assert {:ok, %{token: _, user: _}} = result

    assert {:ok, :complete} = Vxpipe.Identity.Bootstrap.status(deps())
    count_after = length(IdentityAuditStore.recent_events(100))
    assert count_after > count_before
  end

  test "user create with failing audit rolls back atomically" do
    {:ok, %{user: _}} = setup_superadmin()
    actor = real_actor_for_existing!()
    member = member_role!()

    bad_event = %{
      action: String.duplicate("x", 100),
      actor_user_public_id: actor.user_public_id,
      summary: %{}
    }

    assert {:error, _} =
             IdentityUserStore.create(%{
               public_id: Ecto.UUID.generate(),
               email: "rollback@example.com",
               normalized_email: "rollback@example.com",
               password_hash: "hash",
               role_public_id: member.public_id,
               memberships: %{},
               actor_user_public_id: actor.user_public_id,
               actor_session_public_id: actor.session_public_id,
               audit_event: bad_event
             })

    assert {:error, :not_found} = IdentityUserStore.fetch_by_email("rollback@example.com")
  end

  test "installation setup with failing audit rolls back atomically" do
    Repo.get!(AuthenticationInstallation, "default")
    |> AuthenticationInstallation.changeset(%{bootstrap_mode: "operator_required"})
    |> Repo.update!()

    {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)
    bad_event = %{action: String.duplicate("x", 100), summary: %{}}

    assert {:error, _} =
             IdentityInstallationStore.consume_setup_proof(proof, %{
               email: "rollback-setup@example.com",
               normalized_email: "rollback-setup@example.com",
               password_hash: "hash",
               user_public_id: Ecto.UUID.generate(),
               session_public_id: Ecto.UUID.generate(),
               session_digest: String.duplicate("b", 64),
               session_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second),
               audit_event: bad_event
             })

    assert {:error, :not_found} = IdentityUserStore.fetch_by_email("rollback-setup@example.com")

    assert {:ok, status} = Vxpipe.Identity.Bootstrap.status(deps())
    assert status in [:pending_first_run, :pending_operator_proof]
  end

  test "issue_setup_proof fails once installation is complete" do
    {:ok, _} = setup_superadmin()
    assert {:error, :already_completed} = IdentityInstallationStore.issue_setup_proof(900)
  end

  test "setup proof cannot recover a superadmin and recovery proof cannot complete setup" do
    # Force upgraded pending state for setup-proof issuance.
    Repo.get!(AuthenticationInstallation, "default")
    |> AuthenticationInstallation.changeset(%{bootstrap_mode: "operator_required"})
    |> Repo.update!()

    {:ok, %{proof: setup_a}} = IdentityInstallationStore.issue_setup_proof(900)
    {:ok, %{proof: setup_b}} = IdentityInstallationStore.issue_setup_proof(900)
    params = deps()

    assert {:ok, _} =
             Vxpipe.Identity.Bootstrap.complete_with_proof(
               params,
               setup_a,
               "root@example.com",
               "correct horse 15!",
               "correct horse 15!"
             )

    # Leftover setup proof must not be usable for recovery.
    assert {:error, :invalid_proof} =
             Vxpipe.Identity.Bootstrap.recover_with_proof(
               params,
               setup_b,
               "root@example.com",
               "recovered horse 15!!",
               "recovered horse 15!!"
             )

    assert {:ok, %{proof: recovery}} = IdentityInstallationStore.issue_recovery_proof(900)

    # Recovery proof must not complete a (now complete) setup.
    assert {:error, _} =
             IdentityInstallationStore.consume_setup_proof(recovery, %{
               email: "other@example.com",
               normalized_email: "other@example.com",
               password_hash: "hash",
               user_public_id: Ecto.UUID.generate(),
               session_public_id: Ecto.UUID.generate(),
               session_digest: String.duplicate("a", 64),
               session_expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
             })
  end

  defp real_actor_for_existing! do
    {:ok, %{token: token}} =
      Vxpipe.Identity.Sessions.login(deps(), "root@example.com", "correct horse 15!", "127.0.0.1")

    {:ok, principal} = Vxpipe.Identity.Sessions.authenticate(deps(), token)
    Map.from_struct(principal)
  end
end
