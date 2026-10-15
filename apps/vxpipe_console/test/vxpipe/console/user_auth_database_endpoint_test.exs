defmodule Vxpipe.Console.UserAuthDatabaseEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Identity.Bootstrap

  alias Vxpipe.Persistence.{
    IdentityAttemptStore,
    IdentityAuditStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    IdentitySessionStore,
    IdentityUserStore,
    Repo
  }

  @endpoint Vxpipe.Console.Endpoint

  setup do
    if Process.whereis(Repo) == nil, do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    original_deps = Application.get_env(:vxpipe_identity, :dependencies)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    Application.put_env(:vxpipe_identity, :dependencies, dependencies())
    Application.delete_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      restore(:vxpipe_identity, :dependencies, original_deps)
      restore(:vxpipe_console, :user_identity_backend, original_backend)
    end)

    :ok
  end

  test "database-backed setup creates a named session and cannot be replayed" do
    {setup, credentials} = setup_superadmin()
    assert json_response(setup, 200) == %{"ok" => true}

    session = setup |> recycle() |> get("https://localhost/admin/api/session")
    assert %{"user" => %{"email" => "superadmin@example.test"}} = json_response(session, 200)

    replay = post(build_conn(), "https://localhost/auth/api/setup", credentials)
    assert json_response(replay, 409) == %{"error" => %{"code" => "already_complete"}}
  end

  test "self-service password change revokes the old session and accepts the new password" do
    {setup, _credentials} = setup_superadmin()

    changed =
      setup
      |> recycle()
      |> patch("https://localhost/admin/api/account", %{
        "email" => "new-superadmin@example.test",
        "current_password" => "Correct horse battery 15!",
        "password" => "Replacement password 15!",
        "password_confirmation" => "Replacement password 15!"
      })

    assert %{"user" => %{"email" => "new-superadmin@example.test"}} =
             json_response(changed, 200)

    assert %{"error" => %{"code" => "session_required"}} =
             setup
             |> recycle()
             |> get("https://localhost/admin/api/session")
             |> json_response(401)

    new_login =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "new-superadmin@example.test",
        "password" => "Replacement password 15!"
      })

    assert json_response(new_login, 200) == %{"ok" => true}
  end

  test "local recovery proof replaces a Superadmin password and revokes the old session" do
    {setup, _credentials} = setup_superadmin()
    {:ok, %{proof: proof}} = Bootstrap.issue_recovery_proof(dependencies())

    recovered =
      post(build_conn(), "https://localhost/auth/api/recover", %{
        "proof" => proof,
        "email" => "superadmin@example.test",
        "password" => "Recovered password 15!",
        "password_confirmation" => "Recovered password 15!"
      })

    assert json_response(recovered, 200) == %{"ok" => true}

    assert %{"error" => %{"code" => "session_required"}} =
             setup
             |> recycle()
             |> get("https://localhost/admin/api/session")
             |> json_response(401)

    assert %{"user" => %{"email" => "superadmin@example.test"}} =
             recovered
             |> recycle()
             |> get("https://localhost/admin/api/session")
             |> json_response(200)

    replay =
      post(build_conn(), "https://localhost/auth/api/recover", %{
        "proof" => proof,
        "email" => "superadmin@example.test",
        "password" => "Another password 15!",
        "password_confirmation" => "Another password 15!"
      })

    assert %{"error" => %{"code" => "invalid_proof"}} = json_response(replay, 403)
  end

  test "Admin can see protected accounts but cannot reset or create them" do
    {setup, _credentials} = setup_superadmin()
    assert json_response(setup, 200) == %{"ok" => true}

    %{"roles" => roles} =
      setup |> recycle() |> get("https://localhost/admin/api/roles") |> json_response(200)

    admin_role = Enum.find(roles, &(&1["kind"] == "admin"))
    member_role = Enum.find(roles, &is_nil(&1["kind"]))

    admin =
      setup
      |> recycle()
      |> post("https://localhost/admin/api/users", %{
        "email" => "admin@example.test",
        "password" => "Admin initial password 15!",
        "password_confirmation" => "Admin initial password 15!",
        "role_id" => admin_role["id"],
        "memberships" => []
      })

    assert %{"user" => %{"id" => admin_id}} = json_response(admin, 201)

    admin_session =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "admin@example.test",
        "password" => "Admin initial password 15!"
      })

    assert json_response(admin_session, 200) == %{"ok" => true}

    assert %{"user" => %{"id" => ^admin_id}} =
             admin_session
             |> recycle()
             |> get("https://localhost/admin/api/users/#{admin_id}")
             |> json_response(200)

    denied_reset =
      admin_session
      |> recycle()
      |> post("https://localhost/admin/api/users/#{admin_id}/reset-password", %{
        "password" => "Different password 15!",
        "password_confirmation" => "Different password 15!"
      })

    assert json_response(denied_reset, 403) == %{"error" => %{"code" => "forbidden"}}

    denied_create =
      admin_session
      |> recycle()
      |> post("https://localhost/admin/api/users", %{
        "email" => "other-admin@example.test",
        "password" => "Other Admin password 15!",
        "password_confirmation" => "Other Admin password 15!",
        "role_id" => admin_role["id"],
        "memberships" => []
      })

    assert json_response(denied_create, 403) == %{"error" => %{"code" => "forbidden"}}

    member =
      admin_session
      |> recycle()
      |> post("https://localhost/admin/api/users", %{
        "email" => "member@example.test",
        "password" => "Member initial password 15!",
        "password_confirmation" => "Member initial password 15!",
        "role_id" => member_role["id"],
        "memberships" => []
      })

    assert %{"user" => %{"email" => "member@example.test"}} = json_response(member, 201)
  end

  defp setup_superadmin do
    proof =
      case Bootstrap.status(dependencies()) do
        {:ok, :pending_first_run} ->
          nil

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)
          proof
      end

    credentials = %{
      "email" => "superadmin@example.test",
      "password" => "Correct horse battery 15!",
      "password_confirmation" => "Correct horse battery 15!"
    }

    credentials = if proof, do: Map.put(credentials, "proof", proof), else: credentials
    {post(build_conn(), "https://localhost/auth/api/setup", credentials), credentials}
  end

  defp dependencies do
    %{
      users: IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: IdentitySessionStore,
      installations: IdentityInstallationStore,
      attempts: IdentityAttemptStore,
      audit: IdentityAuditStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)
end
