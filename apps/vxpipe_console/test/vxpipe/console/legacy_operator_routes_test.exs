defmodule Vxpipe.Console.LegacyOperatorRoutesTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, get_session: 2]

  alias Vxpipe.Console.Test.FakeUserIdentity

  @endpoint Vxpipe.Console.Endpoint
  @tenant_key "AAAAAAAAAAAAAAAA"
  @call_id "call-public-id"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)

      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    :ok
  end

  test "legacy call pages redirect to exact admin destinations after operator login" do
    authenticated = authenticate()

    for {legacy, destination} <- [
          {"/tenants/#{@tenant_key}/calls", "/admin/tenants/#{@tenant_key}/calls"},
          {"/tenants/#{@tenant_key}/calls/#{@call_id}",
           "/admin/tenants/#{@tenant_key}/calls/#{@call_id}"},
          {"/tenants/#{@tenant_key}/calls/#{@call_id}/console",
           "/admin/tenants/#{@tenant_key}/calls/#{@call_id}"}
        ] do
      conn = authenticated |> recycle() |> https_get(legacy)
      assert redirected_to(conn, 302) == destination
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end
  end

  test "legacy pages require the installation operator session" do
    assert redirected_to(https_get("/tenants/#{@tenant_key}/calls"), 302) == "/auth/login"
  end

  test "legacy UI sign-in redirects to operator login guidance" do
    conn = legacy_session() |> https_get("/operator/sign-in")

    assert redirected_to(conn, 302) == "/auth/login"
    assert get_session(conn, "vxpipe_operator") == nil
  end

  test "installation operator rejection clears a legacy tenant session" do
    conn = legacy_session() |> https_get("/admin")

    assert redirected_to(conn, 302) == "/auth/login"
    assert get_session(conn, "vxpipe_operator") == nil
  end

  test "legacy tenant credential submission is rejected and its session is cleared" do
    conn =
      legacy_session()
      |> post("https://localhost/operator/session", %{
        "operator" => %{"tenant_key" => @tenant_key, "api_key" => "legacy-key"}
      })

    assert response(conn, 410) == "Tenant API-key UI sign-in has been retired."
    assert get_session(conn, "vxpipe_operator") == nil
    refute conn.resp_body =~ "legacy-key"
  end

  defp authenticate do
    post(build_conn(), "https://localhost/auth/api/login", %{
      "email" => FakeUserIdentity.email(),
      "password" => FakeUserIdentity.password()
    })
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp legacy_session do
    build_conn()
    |> init_test_session(%{
      "vxpipe_operator" => %{
        "api_key_id" => "11111111-1111-4111-8111-111111111111",
        "expires_at_unix" => System.system_time(:second) + 300,
        "scopes" => ["calls"],
        "tenant_key" => @tenant_key
      }
    })
  end
end
