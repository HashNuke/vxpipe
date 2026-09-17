defmodule Vxpipe.Console.LegacyOperatorRoutesTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn, only: [get_resp_header: 2, get_session: 2]

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("legacy-operator-routes-secret-", 3)
  @token "legacy-operator-routes-token"
  @tenant_key "AAAAAAAAAAAAAAAA"
  @call_id "call-public-id"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_login_repository()
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
    form = https_get("/auth/login-token/#{@token}")

    form
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => csrf_token(form.resp_body),
      "operator" => %{"token" => @token, "code" => "01234567"}
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

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp configure_login_repository do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(settings, :operator_login_challenge_repository, {
        Vxpipe.Console.Test.OperatorLoginChallengeRepository,
        {self(), :ok}
      })
    )
  end
end
