defmodule Vxpipe.Console.SecurityAuditLoginTest do
  # Regression tests for findings from the 2026-10-14 security audit.
  # See labnotes/milestones/security-audit-remediation.md.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]

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
  @email "superadmin@example.test"
  @password "Correct horse battery 15!"

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

    assert json_response(setup_superadmin(), 200) == %{"ok" => true}
    :ok
  end

  # SEC-1: production reaches /auth only through a same-host proxy, so every client
  # shares the proxy's loopback remote_ip and one per-address throttle bucket.
  test "failed logins from one client behind the proxy do not lock out other clients" do
    for attempt <- 1..30 do
      conn =
        build_conn()
        |> put_req_header("x-forwarded-for", "203.0.113.9")
        |> post("https://localhost/auth/api/login", %{
          "email" => "unknown-#{attempt}@example.test",
          "password" => "Wrong password 123456!"
        })

      assert json_response(conn, 401)
    end

    legitimate =
      build_conn()
      |> put_req_header("x-forwarded-for", "198.51.100.7")
      |> post("https://localhost/auth/api/login", %{"email" => @email, "password" => @password})

    assert json_response(legitimate, 200) == %{"ok" => true}
  end

  # SEC-2: a non-string password reaches Argon2Hasher.verify/2, which has no fallback
  # clause, so existing accounts answer differently from unknown ones.
  test "a non-string password is rejected identically for existing and unknown accounts" do
    unknown =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => "nobody@example.test",
        "password" => ["not", "a", "string"]
      })

    assert json_response(unknown, 401) == %{"error" => %{"code" => "invalid_credentials"}}

    existing =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => @email,
        "password" => ["not", "a", "string"]
      })

    assert json_response(existing, 401) == %{"error" => %{"code" => "invalid_credentials"}}
  end

  # Rejected candidate: the session cookie is Secure because TrustedProxyScheme runs
  # before BrowserSession and Plug marks cookies Secure on HTTPS connections.
  test "the session cookie is marked Secure behind the trusted HTTPS proxy" do
    conn =
      build_conn()
      |> put_req_header("x-forwarded-proto", "https")
      |> post("http://localhost/auth/api/login", %{
        "email" => @email,
        "password" => @password
      })

    assert json_response(conn, 200) == %{"ok" => true}

    cookie_name =
      Application.get_env(:vxpipe_console, :session_cookie_name, "_vxpipe_console_key")

    [session_cookie] =
      conn
      |> get_resp_header("set-cookie")
      |> Enum.filter(&String.starts_with?(&1, cookie_name <> "="))

    assert session_cookie |> String.downcase() |> String.contains?("; secure")
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
      "email" => @email,
      "password" => @password,
      "password_confirmation" => @password
    }

    credentials = if proof, do: Map.put(credentials, "proof", proof), else: credentials
    post(build_conn(), "https://localhost/auth/api/setup", credentials)
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
