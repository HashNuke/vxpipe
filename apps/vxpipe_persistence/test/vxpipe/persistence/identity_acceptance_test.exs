defmodule Vxpipe.Persistence.IdentityAcceptanceTest do
  use Vxpipe.Persistence.DataCase, async: false

  import Ecto.Query

  alias Vxpipe.Identity.{Accounts, Bootstrap, Sessions}

  alias Vxpipe.Persistence.{
    IdentityAttemptStore,
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore
  }

  alias Vxpipe.Persistence.Schema.AuthenticationInstallation

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

  defp setup_superadmin! do
    case Bootstrap.status(deps()) do
      {:ok, :pending_first_run} ->
        {:ok, result} =
          Bootstrap.complete_first_run(
            deps(),
            "root@example.com",
            "correct horse 15!",
            "correct horse 15!"
          )

        result

      {:ok, :pending_operator_proof} ->
        {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

        {:ok, result} =
          Bootstrap.complete_with_proof(
            deps(),
            proof,
            "root@example.com",
            "correct horse 15!",
            "correct horse 15!"
          )

        result
    end
  end

  defp actor!(email \\ "root@example.com") do
    {:ok, %{token: token}} = Sessions.login(deps(), email, "correct horse 15!", "127.0.0.1")
    {:ok, principal} = Sessions.authenticate(deps(), token)
    principal
  end

  defp role!(kind) do
    {:ok, roles} = IdentityRoleStore.list()
    Enum.find(roles, &(&1.kind == kind))
  end

  test "missing installation singleton denies existing sessions and new login" do
    %{token: token} = setup_superadmin!()
    assert {:ok, _} = Sessions.authenticate(deps(), token)

    Repo.delete_all(from(i in AuthenticationInstallation, where: i.key == "default"))

    assert {:error, :missing} = Bootstrap.status(deps())
    assert {:error, :missing} = Sessions.authenticate(deps(), token)

    assert {:error, :missing} =
             Sessions.login(deps(), "root@example.com", "correct horse 15!", "127.0.0.1")
  end

  test "normalized duplicate email is rejected without changing the original account" do
    setup_superadmin!()
    actor = actor!()
    member = role!(:member)

    attrs = %{
      email: "Member@Example.com",
      password: "correct horse 15!",
      password_confirmation: "correct horse 15!",
      role_public_id: member.public_id,
      memberships: %{}
    }

    assert {:ok, created} = Accounts.create_user(deps(), actor, attrs)

    assert {:error, :email_taken} =
             Accounts.create_user(deps(), actor, %{attrs | email: " member@example.COM "})

    assert {:ok, found} = IdentityUserStore.fetch_by_email("member@example.com")
    assert found.public_id == created.public_id
  end

  test "retry after lost setup response cannot reopen setup and original credentials still log in" do
    %{token: token, user: user} = setup_superadmin!()

    assert {:error, :already_completed} =
             Bootstrap.complete_first_run(
               deps(),
               "other@example.com",
               "another horse 15!",
               "another horse 15!"
             )

    assert {:ok, :complete} = Bootstrap.status(deps())
    assert {:ok, _} = Sessions.authenticate(deps(), token)

    assert {:ok, %{user: signed_in}} =
             Sessions.login(deps(), user.email, "correct horse 15!", "127.0.0.1")

    assert signed_in.public_id == user.public_id
  end

  test "concurrent attempts to remove both Superadmins retain one enabled Superadmin" do
    %{user: first} = setup_superadmin!()
    actor = actor!()
    superadmin = role!(:superadmin)
    member = role!(:member)

    assert {:ok, second} =
             Accounts.create_user(deps(), actor, %{
               email: "second@example.com",
               password: "correct horse 15!",
               password_confirmation: "correct horse 15!",
               role_public_id: superadmin.public_id,
               memberships: %{}
             })

    second_actor = actor!("second@example.com")

    results =
      [{actor, first.public_id}, {second_actor, second.public_id}]
      |> Task.async_stream(
        fn {acting, target_id} ->
          Accounts.update_user(deps(), acting, target_id, %{role_public_id: member.public_id})
        end,
        max_concurrency: 2,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, :last_superadmin}, &1)) == 1
    assert {:ok, 1} = IdentityUserStore.count_enabled_superadmins()
  end
end
