defmodule Vxpipe.Console.MCPOAuthEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]
  alias Vxpipe.Console.Test.{FakeUserIdentity, MCPManagementFixture}
  @endpoint Vxpipe.Console.Endpoint
  @tenant "AAAAAAAAAAAAAAAA"
  @path "/api/tenants/#{@tenant}/mcp-connections"

  setup do
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.merge(calls,
        credential_repository: {MCPManagementFixture, self()},
        mcp_connection_repository: {MCPManagementFixture, self()},
        mcp_connection_probe: {MCPManagementFixture, self()},
        mcp_preflight: {MCPManagementFixture, self()},
        mcp_oauth_preparation: {MCPManagementFixture, self()},
        mcp_oauth_completion: {MCPManagementFixture, self()},
        mcp_oauth_attempt_repository: {MCPManagementFixture, self()}
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    end)

    :ok
  end

  test "preflight supplies the installation callback for manual registration without starting consent" do
    response =
      login()
      |> recycle()
      |> post("https://localhost/api/tenants/#{@tenant}/mcp-discovery", %{
        "endpoint" => "https://mcp.example.test/mcp",
        "revision" => "draft"
      })

    assert json_response(response, 200)["discovery"]["oauth_client"]["callback_url"] ==
             "https://console.example.test/oauth/mcp/callback"

    refute_received {:oauth_attempt_saved, _, _}
    refute_received {:oauth_prepared, _}
  end

  test "OAuth start requires session and CSRF and only returns handoff after persistence" do
    path = "https://localhost/api/tenants/#{@tenant}/mcp-oauth"

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "revision" => "draft",
      "auth_method" => "cimd"
    }

    assert build_conn() |> post(path, input) |> json_response(401)
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", "bad")
      |> post(path, input)
    end

    refute_received {:oauth_prepared, _}

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, input)

    body = json_response(conn, 201)
    assert body["authorization_url"] == "https://auth.example.test/authorize?state=opaque"
    assert body["attempt_id"] == "attempt-id"
    refute conn.resp_body =~ "private-verifier"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert_receive {:oauth_prepared, @tenant}
    assert_receive {:oauth_attempt_saved, @tenant, attributes}
    assert attributes.installation_revision == 2
    assert (build_conn() |> post("https://localhost/api/platform/mcp-oauth", input)).status == 404
  end

  test "OAuth reconnect is session and CSRF protected and binds the saved generation" do
    path = "https://localhost" <> @path <> "/oauth-connection/oauth"

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "revision" => "draft",
      "auth_method" => "dcr",
      "generation" => 7
    }

    assert build_conn() |> post(path, input) |> json_response(401)
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", "bad")
      |> post(path, input)
    end

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, input)

    assert json_response(conn, 201)["connection_id"] == "oauth-connection"
    assert_receive {:oauth_attempt_saved, @tenant, %{operation: "replace", generation: 7}}
    refute conn.resp_body =~ "private"

    stale =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, %{input | "generation" => 6})

    assert json_response(stale, 409)["error"]["code"] == "stale_mcp_connection"
  end

  test "OAuth start returns bounded existing or reconnect proposals before protocol preparation" do
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    for {suffix, expected} <- [
          {"existing",
           %{"code" => "mcp_connection_exists", "connection_id" => "existing-connection"}},
          {"revoked",
           %{
             "code" => "mcp_reconnect_required",
             "connection_id" => "revoked-connection",
             "generation" => 4
           }}
        ] do
      response =
        page
        |> recycle()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> post("https://localhost/api/tenants/#{@tenant}/mcp-oauth", %{
          "endpoint" => "https://mcp.example.test/" <> suffix,
          "revision" => "draft",
          "auth_method" => "dcr",
          "initial_access_token" => "private-registration"
        })

      assert json_response(response, 409) == %{"error" => expected}
      refute response.resp_body =~ "private-registration"
      assert get_resp_header(response, "cache-control") == ["private, no-store"]
    end

    refute_received {:oauth_prepared, _}
    refute_received {:oauth_attempt_saved, _, _}
  end

  test "rate-limited OAuth preparation returns a retryable response before issuing an attempt" do
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    for suffix <- ["/mcp-oauth", "/mcp-connections/oauth-connection/oauth"] do
      response =
        page
        |> recycle()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> post("https://localhost/api/tenants/#{@tenant}" <> suffix, %{
          "endpoint" => "https://mcp.example.test/mcp",
          "revision" => "busy",
          "auth_method" => "dcr",
          "generation" => 7
        })

      assert json_response(response, 429)["error"]["code"] == "mcp_connection_busy"
    end

    refute_received {:oauth_attempt_saved, _, _}
  end

  test "Own-client configuration errors offer recovery without creating a consent attempt" do
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    for {revision, code} <- [
          {"invalid-own", "invalid_own_oauth_configuration"},
          {"machine-grant", "oauth_browser_grant_required"}
        ],
        suffix <- ["/mcp-oauth", "/mcp-connections/oauth-connection/oauth"] do
      response =
        page
        |> recycle()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> post("https://localhost/api/tenants/#{@tenant}" <> suffix, %{
          "endpoint" => "https://mcp.example.test/mcp",
          "revision" => revision,
          "auth_method" => "own_client",
          "generation" => 7
        })

      assert json_response(response, 422)["error"]["code"] == code
    end

    refute_received {:oauth_attempt_saved, _, _}
  end

  test "OAuth return context is validated before preparation and restored from the claimed attempt" do
    path = "https://localhost/api/tenants/#{@tenant}/mcp-oauth"
    return_to = "/t/#{@tenant}/services/search?q=calendar&cursor=page-2"

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "revision" => "draft",
      "auth_method" => "cimd",
      "return_to" => return_to
    }

    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    for invalid <- ["https://other.test", "/t/BBBBBBBBBBBBBBBB/services"] do
      conn =
        page
        |> recycle()
        |> enforce_csrf()
        |> put_req_header("x-csrf-token", csrf)
        |> post(path, %{input | "return_to" => invalid})

      assert json_response(conn, 422)["error"]["code"] == "invalid_oauth_return_location"
      refute_received {:oauth_prepared, _}
    end

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, input)

    assert json_response(conn, 201)["attempt_id"] == "attempt-id"
    assert_receive {:oauth_attempt_saved, @tenant, attributes}
    assert attributes.return_to == return_to
    assert_receive {:oauth_preparation_input, protocol_input}
    refute Map.has_key?(protocol_input, "return_to")

    query =
      URI.encode_query(%{
        "state" => String.duplicate("r", 43),
        "code" => "code",
        "iss" => "https://auth.example.test",
        "return_to" => "https://other.test"
      })

    callback = page |> recycle() |> get("https://localhost/oauth/mcp/callback?" <> query)
    location = URI.parse(redirected_to(callback, 303))
    assert location.path == "/t/#{@tenant}/services/search"

    assert URI.decode_query(location.query) == %{
             "q" => "calendar",
             "cursor" => "page-2",
             "mcp" => "connected",
             "mcp_attempt" => "attempt-id"
           }
  end

  test "OAuth callback requires session, claims state and redirects without code or tokens" do
    query =
      URI.encode_query(%{
        "state" => String.duplicate("s", 43),
        "code" => "private-code",
        "iss" => "https://auth.example.test"
      })

    path = "https://localhost/oauth/mcp/callback?" <> query
    assert build_conn() |> get(path) |> json_response(401)
    conn = login() |> recycle() |> get(path)

    assert redirected_to(conn, 303) ==
             "/t/#{@tenant}/services?mcp=connected&mcp_attempt=attempt-id"

    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert_receive {:oauth_claimed, @tenant}
    assert_receive {:oauth_completed, @tenant}
    assert_receive {:oauth_connection_saved, @tenant}
    refute conn.resp_body =~ "private"
  end

  test "claimed OAuth denial or check failure returns only trusted recovery context" do
    for {response, status} <- [
          {%{"error" => "access_denied"}, "denied"},
          {%{"code" => "check-failed"}, "failed"}
        ] do
      query =
        URI.encode_query(
          Map.merge(
            %{
              "state" => String.duplicate("r", 43),
              "iss" => "https://auth.example.test",
              "return_to" => "https://attacker.test",
              "mcp_attempt" => "attacker-attempt"
            },
            response
          )
        )

      conn = login() |> recycle() |> get("https://localhost/oauth/mcp/callback?" <> query)
      location = URI.parse(redirected_to(conn, 303))
      assert location.path == "/t/#{@tenant}/services/search"

      assert URI.decode_query(location.query) == %{
               "q" => "calendar",
               "cursor" => "page-2",
               "mcp" => status,
               "mcp_attempt" => "attempt-id"
             }

      assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
      refute_received {:oauth_connection_saved, _}
    end
  end

  test "unclaimed callback state cannot supply a recovery destination" do
    query =
      URI.encode_query(%{
        "state" => String.duplicate("x", 43),
        "error" => "access_denied",
        "iss" => "https://auth.example.test",
        "return_to" => "/t/#{@tenant}/services"
      })

    conn = login() |> recycle() |> get("https://localhost/oauth/mcp/callback?" <> query)
    assert json_response(conn, 400)["error"]["code"] == "oauth_attempt_unavailable"
    assert get_resp_header(conn, "location") == []
  end

  test "ambiguous callback query is rejected before claiming state" do
    path = "https://localhost/oauth/mcp/callback?state=#{String.duplicate("s", 43)}&code=a&code=b"
    conn = login() |> recycle() |> get(path)
    assert json_response(conn, 400)["error"]["code"] == "invalid_oauth_callback"
    refute_received {:oauth_claimed, _}
  end

  defp enforce_csrf(conn),
    do: %{conn | private: Map.delete(conn.private, :plug_skip_csrf_protection)}

  defp login,
    do:
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
end
