defmodule Vxpipe.Console.OperatorLoginFlowTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ConnTest

  @endpoint Vxpipe.Console.Endpoint
  @secret String.duplicate("operator-login-flow-secret-", 3)
  @token "operator-login-test-token"

  setup do
    original_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    original_secret = Application.fetch_env!(:vxpipe_console, :operator_login_secret)
    original_cookie_name = Application.get_env(:vxpipe_console, :session_cookie_name)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, original_calls)
      Application.put_env(:vxpipe_console, :operator_login_secret, original_secret)

      if original_cookie_name do
        Application.put_env(:vxpipe_console, :session_cookie_name, original_cookie_name)
      else
        Application.delete_env(:vxpipe_console, :session_cookie_name)
      end
    end)

    Application.put_env(:vxpipe_console, :operator_login_secret, @secret)
    configure_repository(:ok)
    :ok
  end

  test "guides anonymous operators without issuing a challenge" do
    conn = https_get("/auth/login")

    body = html_response(conn, 200)
    assert body =~ "mix vxpipe.login"
    refute body =~ "API key"
    assert private_auth_response?(conn)
  end

  test "renders the path token into the server-owned code-entry form" do
    form_conn = https_get("/auth/login-token/#{@token}")
    body = html_response(form_conn, 200)

    assert body =~ "Enter the 8-digit code"
    assert body =~ ~s(action="/auth/login-token")
    assert body =~ ~s(name="operator[token]")
    assert body =~ ~s(value="#{@token}")
    assert private_auth_response?(form_conn)
  end

  test "filters the path token from Phoenix logs" do
    log =
      capture_log([level: :debug], fn ->
        assert https_get("/auth/login-token/#{@token}") |> html_response(200) =~
                 "Enter the 8-digit code"
      end)

    refute log =~ @token
    assert log =~ ~s("token" => "[FILTERED]")
  end

  test "exchanges the code once, rotates the session, and protects HTML and JSON admin routes" do
    form_conn = https_get("/auth/login-token/#{@token}")
    [pre_auth_cookie] = Plug.Conn.get_resp_header(form_conn, "set-cookie")

    authenticated = post_challenge(form_conn, @token, "01234567")

    assert redirected_to(authenticated, 302) == "/admin"
    [session_cookie] = Plug.Conn.get_resp_header(authenticated, "set-cookie")
    refute cookie_value(session_cookie) == cookie_value(pre_auth_cookie)
    assert session_cookie =~ "HttpOnly"
    assert session_cookie =~ "SameSite=Lax"
    assert session_cookie =~ "; secure;"
    assert_receive {:operator_login_challenge_consumed, token_digest, code_verifier}
    assert byte_size(token_digest) == 32
    assert byte_size(code_verifier) == 32

    admin = authenticated |> recycle() |> https_get("/admin")
    body = html_response(admin, 200)
    assert body =~ ~s(id="admin-root")
    assert body =~ ~s(src="/assets/admin.js")
    assert private_auth_response?(admin)

    api = authenticated |> recycle() |> https_get("/admin/api/session")
    assert %{"operator" => true, "expires_at" => expires_at} = json_response(api, 200)
    assert is_binary(expires_at)
    assert private_auth_response?(api)
  end

  test "two checkout cookies on the same hostname retain independent operator sessions" do
    Application.put_env(:vxpipe_console, :session_cookie_name, "_checkout_a")
    authenticated_a = post_challenge(https_get("/auth/login-token/#{@token}"), @token, "01234567")
    assert Map.has_key?(authenticated_a.resp_cookies, "_checkout_a")

    Application.put_env(:vxpipe_console, :session_cookie_name, "_checkout_b")
    other = authenticated_a |> recycle() |> https_get("/admin/api/session")
    assert other.status == 401
    form_b = other |> recycle() |> https_get("/auth/login-token/#{@token}")
    authenticated_b = post_challenge(form_b, @token, "01234567")
    assert Map.has_key?(authenticated_b.resp_cookies, "_checkout_b")
    assert Map.has_key?(authenticated_b.req_cookies, "_checkout_a")

    Application.put_env(:vxpipe_console, :session_cookie_name, "_checkout_a")
    session_a = authenticated_b |> recycle() |> https_get("/admin/api/session")
    assert %{"operator" => true} = json_response(session_a, 200)

    Application.put_env(:vxpipe_console, :session_cookie_name, "_checkout_b")
    session_b = session_a |> recycle() |> https_get("/admin/api/session")
    assert %{"operator" => true} = json_response(session_b, 200)
  end

  test "uses one generic response for unknown, expired, exhausted, and consumed challenges" do
    for reason <- [:unknown, :expired, :exhausted, :consumed] do
      configure_repository({:error, reason})
      token = "#{@token}-#{reason}"
      response = post_challenge(https_get("/auth/login-token/#{token}"), token, "87654321")

      body = html_response(response, 422)
      assert body =~ "That login request is no longer available."
      assert body =~ "mix vxpipe.login"
      refute body =~ Atom.to_string(reason)
      assert private_auth_response?(response)
    end
  end

  test "filters token and code from logs and router completion telemetry" do
    form_conn = https_get("/auth/login-token/#{@token}")
    handler_id = "operator-login-secrets-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:phoenix, :router_dispatch, :start], [:phoenix, :router_dispatch, :stop]],
        &Vxpipe.Console.Test.OperatorLoginChallengeRepository.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    log =
      capture_log([level: :debug], fn ->
        response = post_encoded_challenge(form_conn, @token, "01234567")
        assert redirected_to(response, 302) == "/admin"
      end)

    refute log =~ @token
    refute log =~ "01234567"

    metadata =
      for _index <- 1..2 do
        assert_receive {:operator_login_router_telemetry, _phase, event_metadata}
        event_metadata
      end

    inspected = inspect_project_metadata(metadata)
    refute inspected =~ @token
    refute inspected =~ "01234567"
  end

  test "keeps credentials out of exception telemetry when challenge consumption raises" do
    form_conn = https_get("/auth/login-token/#{@token}")
    handler_id = "operator-login-exception-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        [[:phoenix, :router_dispatch, :exception], [:phoenix, :error_rendered]],
        &Vxpipe.Console.Test.OperatorLoginChallengeRepository.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    configure_repository(:raise)

    assert_raise RuntimeError, "forced operator login repository error", fn ->
      post_encoded_challenge(form_conn, @token, "01234567")
    end

    assert_receive {:operator_login_router_telemetry, :exception, exception_metadata}
    assert_receive {:operator_login_router_telemetry, :error_rendered, rendered_metadata}

    inspected = inspect_project_metadata([exception_metadata, rendered_metadata])
    refute inspected =~ @token
    refute inspected =~ "01234567"
  end

  test "redacts malformed login fields before router completion telemetry" do
    form_conn = https_get("/auth/login-token/#{@token}")
    malformed_code = "malformed-code-secret"
    handler_id = "operator-login-malformed-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:phoenix, :router_dispatch, :stop],
        &Vxpipe.Console.Test.OperatorLoginChallengeRepository.handle_telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    body =
      "_csrf_token=#{URI.encode_www_form(csrf_token(form_conn.resp_body))}" <>
        "&operator%5Btoken%5D=#{URI.encode_www_form(@token)}" <>
        "&operator%5Bcode%5D%5B%5D=#{URI.encode_www_form(malformed_code)}"

    response =
      form_conn
      |> recycle()
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("https://localhost/auth/login-token", body)

    assert html_response(response, 422) =~ "That login request is no longer available."
    assert_receive {:operator_login_router_telemetry, :stop, metadata}

    inspected = inspect_project_metadata([metadata])
    refute inspected =~ @token
    refute inspected =~ malformed_code
  end

  test "rejects a missing CSRF token before consuming the challenge" do
    form_conn = https_get("/auth/login-token/#{@token}")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      form_conn
      |> recycle()
      |> then(&%{&1 | private: Map.delete(&1.private, :plug_skip_csrf_protection)})
      |> post("https://localhost/auth/login-token", %{
        "operator" => %{"token" => @token, "code" => "01234567"}
      })
    end

    refute_received {:operator_login_challenge_consumed, _, _}
  end

  test "redirects anonymous HTML sessions and rejects anonymous JSON" do
    html_conn = https_get("/admin")
    assert redirected_to(html_conn, 302) == "/auth/login"
    assert private_auth_response?(html_conn)

    api_conn = https_get("/admin/api/session")
    assert json_response(api_conn, 401) == %{"error" => %{"code" => "operator_session_required"}}
    assert private_auth_response?(api_conn)
  end

  test "sign out drops the operator session and returns to token-free login" do
    authenticated = authenticate()
    admin = authenticated |> recycle() |> https_get("/admin")
    csrf_token = Plug.CSRFProtection.get_csrf_token()

    signed_out =
      admin
      |> recycle()
      |> post("https://localhost/auth/logout", %{"_csrf_token" => csrf_token})

    assert redirected_to(signed_out, 302) == "/auth/login"
    assert signed_out |> recycle() |> https_get("/admin") |> redirected_to(302) == "/auth/login"
  end

  test "rejects public plain HTTP even with a loopback Host header" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 4})
      |> get("http://localhost/auth/login-token")

    assert response(conn, 404) == "not found"
    refute_received {:operator_login_challenge_consumed, _, _}

    resource_conn =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 4})
      |> get("http://localhost/tenants/tenantkey1234567/calls/call-id/inspection")

    assert response(resource_conn, 404) == "not found"
  end

  test "permits HTTP only when both the peer and requested host are loopback" do
    conn =
      build_conn()
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> get("http://127.0.0.1/auth/login")

    assert html_response(conn, 200) =~ "mix vxpipe.login"
  end

  test "trusts forwarded HTTPS only from a loopback reverse proxy" do
    proxied =
      build_conn()
      |> Map.put(:remote_ip, {127, 0, 0, 1})
      |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
      |> get("http://console.example.test/auth/login")

    assert html_response(proxied, 200) =~ "mix vxpipe.login"

    spoofed =
      build_conn()
      |> Map.put(:remote_ip, {203, 0, 113, 4})
      |> Plug.Conn.put_req_header("x-forwarded-proto", "https")
      |> get("http://console.example.test/auth/login")

    assert response(spoofed, 404) == "not found"
  end

  defp authenticate,
    do: post_challenge(https_get("/auth/login-token/#{@token}"), @token, "01234567")

  defp post_challenge(form_conn, token, code) do
    form_conn
    |> recycle()
    |> post("https://localhost/auth/login-token", %{
      "_csrf_token" => csrf_token(form_conn.resp_body),
      "operator" => %{"token" => token, "code" => code}
    })
  end

  defp post_encoded_challenge(form_conn, token, code) do
    body =
      URI.encode_query(%{
        "_csrf_token" => csrf_token(form_conn.resp_body),
        "operator[token]" => token,
        "operator[code]" => code
      })

    form_conn
    |> recycle()
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post("https://localhost/auth/login-token", body)
  end

  defp https_get(conn \\ build_conn(), path), do: get(conn, "https://localhost#{path}")

  defp configure_repository(result) do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(
        settings,
        :operator_login_challenge_repository,
        {Vxpipe.Console.Test.OperatorLoginChallengeRepository, {self(), result}}
      )
    )
  end

  defp csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end

  defp cookie_value(cookie), do: cookie |> String.split(";", parts: 2) |> hd()

  defp inspect_project_metadata(metadata_entries) do
    metadata_entries
    |> Enum.map(fn metadata ->
      case metadata do
        %{conn: conn} ->
          {
            Map.delete(metadata, :conn),
            %{
              params: conn.params,
              body_params: conn.body_params,
              query_params: conn.query_params,
              private: conn.private
            }
          }

        other ->
          other
      end
    end)
    |> inspect(limit: :infinity, printable_limit: :infinity)
  end

  defp private_auth_response?(conn) do
    Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"] and
      Plug.Conn.get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end
end
