defmodule Vxpipe.Console.ProductRolesTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Identity.{Accounts, Bootstrap, Sessions}
  alias Vxpipe.Persistence.{Repo, IdentityInstallationStore, IdentityRoleStore}
  @endpoint Endpoint
  @password "local-account-password-15!"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)

    for {app, key} <- [
          {:vxpipe_identity, :dependencies},
          {:vxpipe_console, :user_identity_backend},
          {:vxpipe_console, :telephony_host}
        ] do
      original = Application.fetch_env(app, key)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(app, key, value)
          :error -> Application.delete_env(app, key)
        end
      end)
    end

    deps = %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }

    Application.put_env(:vxpipe_identity, :dependencies, deps)
    Application.put_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    bootstrap =
      case Bootstrap.status(deps) do
        {:ok, :pending_first_run} ->
          Bootstrap.complete_first_run(deps, "accounts-root@example.test", @password, @password)

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

          Bootstrap.complete_with_proof(
            deps,
            proof,
            "accounts-root@example.test",
            @password,
            @password
          )
      end

    {:ok, %{user: root}} = bootstrap
    {:ok, %{token: token}} = Sessions.login(deps, root.email, @password, "local")
    {:ok, actor} = Sessions.authenticate(deps, token)

    auth =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => root.email,
        "password" => @password
      })

    %{deps: deps, actor: actor, root: root, auth: auth}
  end

  test "canonical and legacy role pages share bounded projection and exact detail counts", c do
    for prefix <- ["/api", "/admin/api"] do
      page =
        c.auth |> recycle() |> get(prefix <> "/roles?page=1&page_size=1") |> json_response(200)

      assert %{
               "roles" => [role],
               "pagination" => %{"page" => 1, "page_size" => 1, "total" => total}
             } = page

      assert total >= 2
      assert Map.keys(role) |> Enum.sort() == ~w(grants id kind name revision)
      detail = c.auth |> recycle() |> get(prefix <> "/roles/" <> role["id"]) |> json_response(200)
      assert detail["role"] == role
      assert is_integer(detail["affected_users"])

      for query <- ["page=0", "page_size=51", "page=999999", "query=ignored"] do
        assert c.auth |> recycle() |> get(prefix <> "/roles?" <> query) |> json_response(422)
      end

      assert c.auth |> recycle() |> get(prefix <> "/roles/not-a-role") |> json_response(404)
    end
  end

  test "role CRUD keeps revisions, protected roles and affected-user authority", c do
    body = %{
      "name" => "Canonical reviewer",
      "grants" => [%{"permission" => "calls.read", "scope" => "assigned_tenants"}]
    }

    created = c.auth |> recycle() |> post("/api/roles", body) |> json_response(201)
    id = created["role"]["id"]
    assert created["role"]["revision"] == 1

    updated =
      c.auth
      |> recycle()
      |> patch(
        "/api/roles/" <> id,
        Map.merge(body, %{"name" => "Updated reviewer", "expected_revision" => 1})
      )
      |> json_response(200)

    assert updated["role"]["revision"] == 2

    assert c.auth
           |> recycle()
           |> patch("/api/roles/" <> id, Map.put(body, "expected_revision", 1))
           |> json_response(409)

    assert c.auth |> recycle() |> delete("/api/roles/" <> id) |> response(204)

    assert c.auth
           |> recycle()
           |> delete("/api/roles/" <> c.root.role_public_id)
           |> json_response(403)
  end

  test "reset password preserves target-category authorization and invalidates old sessions", c do
    {:ok, member} = IdentityRoleStore.fetch_by_slug("tenant-manager")

    {:ok, user} =
      Accounts.create_user(c.deps, c.actor, %{
        email: "reset-target@example.test",
        password: @password,
        password_confirmation: @password,
        role_public_id: member.public_id,
        memberships: %{}
      })

    {:ok, %{token: token}} = Sessions.login(c.deps, user.email, @password, "local")

    for prefix <- ["/api", "/admin/api"] do
      assert c.auth
             |> recycle()
             |> post(prefix <> "/users/#{user.public_id}/reset-password", %{
               "password" => "replacement-local-password!",
               "password_confirmation" => "replacement-local-password!"
             })
             |> response(204)
    end

    assert {:error, _} = Sessions.authenticate(c.deps, token)
    assert {:error, _} = Sessions.login(c.deps, user.email, @password, "local")
    assert {:ok, _} = Sessions.login(c.deps, user.email, "replacement-local-password!", "local")
    {:ok, admin_role} = IdentityRoleStore.fetch_by_slug("admin")

    {:ok, admin} =
      Accounts.create_user(c.deps, c.actor, %{
        email: "reset-admin@example.test",
        password: @password,
        password_confirmation: @password,
        role_public_id: admin_role.public_id,
        memberships: %{}
      })

    auth =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => admin.email,
        "password" => @password
      })

    denied =
      auth
      |> recycle()
      |> post("/api/users/#{c.root.public_id}/reset-password", %{
        "password" => "must-not-be-echoed",
        "password_confirmation" => "must-not-be-echoed"
      })

    assert json_response(denied, 403) == %{"error" => %{"code" => "forbidden"}}
    refute denied.resp_body =~ "must-not-be-echoed"
  end

  test "session-only aliases reject explicit authorization before cookies or body parsing", c do
    for prefix <- ["/api", "/admin/api"],
        {method, path} <- [
          {"GET", "/roles"},
          {"GET", "/roles/role"},
          {"POST", "/roles"},
          {"PATCH", "/roles/role"},
          {"DELETE", "/roles/role"},
          {"POST", "/users/user/reset-password"}
        ] do
      conn =
        c.auth
        |> recycle()
        |> put_req_header("authorization", "Bearer synthetic")
        |> put_req_header("content-type", "application/json")

      assert dispatch(conn, @endpoint, method, prefix <> path, "malformed") |> json_response(401) ==
               %{"error" => %{"code" => "session_required"}}

      assert dispatch(build_conn(), @endpoint, method, "https://localhost" <> prefix <> path, %{})
             |> json_response(401)
    end
  end

  test "canonical role and password writes retain CSRF and host exclusions", c do
    page = c.auth |> recycle() |> get("/roles")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    for path <- ["/api/roles", "/api/users/#{c.root.public_id}/reset-password"] do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        page
        |> recycle()
        |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
        |> put_req_header("x-csrf-token", "invalid")
        |> post(path, %{})
      end
    end

    assert page
           |> recycle()
           |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
           |> put_req_header("x-csrf-token", csrf)
           |> post("/api/roles", %{"name" => "CSRF reviewer", "grants" => []})
           |> json_response(201)

    assert build_conn() |> get("http://public.example/api/roles") |> response(404)
    Application.put_env(:vxpipe_console, :telephony_host, "carrier.example")
    assert build_conn() |> get("https://carrier.example/api/roles") |> response(404)
  end
end
