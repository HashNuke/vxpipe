defmodule Vxpipe.Console.OperatorLoginFlowTest do
  @moduledoc """
  Legacy operator challenge flow is retired.

  Asserts that `/auth/login-token` challenges cannot authenticate and that
  the named `UserSession` (`/auth/api/login`) path owns Console access.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Vxpipe.Console.Test.FakeUserIdentity

  @endpoint Vxpipe.Console.Endpoint
  @legacy_token "operator-login-test-token"

  setup do
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    :ok
  end

  test "email login pages load the Console application" do
    for path <- ["/auth/login", "/auth/setup"] do
      response = get(build_conn(), "https://localhost#{path}")
      assert html_response(response, 200) =~ ~s(id="admin-root")
      assert private_auth_response?(response)
    end
  end

  test "legacy login-token routes are removed" do
    assert get(build_conn(), "https://localhost/auth/login-token/#{@legacy_token}").status == 404

    assert post(build_conn(), "https://localhost/auth/login-token", %{
             "operator" => %{"token" => @legacy_token, "code" => "01234567"}
           }).status == 404
  end

  test "legacy installation operator sessions cannot authenticate" do
    legacy =
      build_conn()
      |> Map.put(:host, "localhost")
      |> Map.put(:scheme, :https)
      |> Plug.Test.init_test_session(%{
        "vxpipe_installation_operator" => %{
          "authority" => "installation_operator",
          "issued_at_unix" => System.system_time(:second),
          "expires_at_unix" => System.system_time(:second) + 3600,
          "signature" => "legacy"
        }
      })

    assert redirected_to(legacy |> recycle() |> get("https://localhost/admin"), 302) ==
             "/auth/login"

    assert json_response(legacy |> recycle() |> get("https://localhost/admin/api/session"), 401) ==
             %{"error" => %{"code" => "session_required"}}
  end

  test "redirects anonymous HTML sessions and rejects anonymous JSON with the user code" do
    html_conn = https_get("/admin")
    assert redirected_to(html_conn, 302) == "/auth/login"
    assert private_auth_response?(html_conn)

    api_conn = https_get("/admin/api/session")
    assert json_response(api_conn, 401) == %{"error" => %{"code" => "session_required"}}
    assert private_auth_response?(api_conn)
  end

  test "named user sessions reach HTML and JSON admin routes" do
    authenticated = authenticate()

    legacy = authenticated |> recycle() |> https_get("/admin")
    assert redirected_to(legacy) == "/"
    admin = authenticated |> recycle() |> https_get("/account")
    assert html_response(admin, 200) =~ ~s(id="admin-root")
    assert private_auth_response?(admin)

    session = authenticated |> recycle() |> https_get("/admin/api/session")
    assert %{"user" => %{"email" => "owner@example.test"}} = json_response(session, 200)
  end

  test "sign out drops the named user session and returns to email login" do
    authenticated = authenticate()
    csrf = Plug.CSRFProtection.get_csrf_token()

    signed_out =
      authenticated
      |> recycle()
      |> post("https://localhost/auth/logout", %{"_csrf_token" => csrf})

    assert redirected_to(signed_out, 302) == "/auth/login"
    assert signed_out |> recycle() |> https_get("/admin") |> redirected_to(302) == "/auth/login"
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp private_auth_response?(conn) do
    Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"] and
      Plug.Conn.get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end
end
