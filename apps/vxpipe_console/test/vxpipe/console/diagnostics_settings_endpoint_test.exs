defmodule Vxpipe.Console.DiagnosticsSettingsEndpointTest do
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

  for kind <- ["admin", "superadmin"] do
    @kind kind
    test "#{kind} can manage Diagnostics while URL access remains separate" do
      {session, _} = setup_superadmin()

      user =
        Repo.get_by!(Vxpipe.Persistence.Schema.IdentityUser,
          normalized_email: "superadmin@example.test"
        )

      role = Repo.get_by!(Vxpipe.Persistence.Schema.IdentityRole, kind: @kind)
      Repo.update!(Ecto.Changeset.change(user, role_id: role.id))
      path = "https://localhost/api/installation/diagnostics"

      assert %{"enabled" => false, "revision" => 0} =
               session |> recycle() |> get(path) |> json_response(200)

      assert %{"enabled" => true, "revision" => 1} =
               session
               |> recycle()
               |> patch(path, %{enabled: true, revision: 0})
               |> json_response(200)

      assert %{"enabled" => true, "revision" => 1} =
               session |> recycle() |> get(path) |> json_response(200)

      assert %{"error" => %{"code" => "conflict"}} =
               session
               |> recycle()
               |> patch(path, %{enabled: false, revision: 0})
               |> json_response(409)

      assert %{"error" => %{"code" => "invalid_enabled"}} =
               session
               |> recycle()
               |> patch(path, %{enabled: "true", revision: 1})
               |> json_response(422)

      assert session
             |> recycle()
             |> get("https://localhost/platform/installation")
             |> html_response(200) =~ "admin-root"

      status = if @kind == "superadmin", do: 200, else: 403

      assert session
             |> recycle()
             |> get("https://localhost/api/installation")
             |> json_response(status)
    end
  end

  test "custom role sessions cannot read, change or open Diagnostics" do
    {session, _} = setup_superadmin()

    user =
      Repo.get_by!(Vxpipe.Persistence.Schema.IdentityUser,
        normalized_email: "superadmin@example.test"
      )

    role =
      Repo.insert!(
        Vxpipe.Persistence.Schema.IdentityRole.ordinary_changeset(
          %Vxpipe.Persistence.Schema.IdentityRole{},
          %{public_id: Ecto.UUID.generate(), slug: "diagnostics-reader", name: "Reader"}
        )
      )

    Repo.update!(Ecto.Changeset.change(user, role_id: role.id))
    path = "https://localhost/api/installation/diagnostics"

    assert session |> recycle() |> get(path) |> json_response(403) == %{
             "error" => %{"code" => "forbidden"}
           }

    assert session
           |> recycle()
           |> patch(path, %{enabled: true, revision: 0})
           |> json_response(403) == %{"error" => %{"code" => "forbidden"}}

    assert session |> recycle() |> get("https://localhost/platform/installation") |> response(403)

    assert {:ok, %{enabled: false, revision: 0}} =
             Vxpipe.Persistence.DiagnosticsSettingsStore.snapshot()
  end

  test "anonymous and bearer-only requests cannot access the setting" do
    path = "https://localhost/api/installation/diagnostics"

    assert build_conn() |> get(path) |> json_response(401) == %{
             "error" => %{"code" => "session_required"}
           }

    assert build_conn()
           |> Plug.Conn.put_req_header("authorization", "Bearer synthetic-machine-token")
           |> patch(path, %{enabled: true, revision: 0})
           |> json_response(401) == %{"error" => %{"code" => "session_required"}}
  end

  test "unavailable settings storage is an explicit error" do
    {session, _} = setup_superadmin()
    Repo.query!("DELETE FROM installation_diagnostics_settings")

    assert session
           |> recycle()
           |> get("https://localhost/api/installation/diagnostics")
           |> json_response(503) == %{"error" => %{"code" => "unavailable"}}
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
      "public_url" => "https://CALLS.example.test:8443/setup?initial=1",
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
      diagnostics_settings: Vxpipe.Persistence.DiagnosticsSettingsStore,
      attempts: IdentityAttemptStore,
      audit: IdentityAuditStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)
end
