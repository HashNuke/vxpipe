defmodule Vxpipe.Console.MCPConnectionsEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3, get_resp_header: 2]
  alias Vxpipe.Console.Test.{FakeUserIdentity, MCPStaticManagementFixture}
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
        credential_repository: {MCPStaticManagementFixture, self()},
        mcp_connection_repository: {MCPStaticManagementFixture, self()},
        mcp_connection_probe: {MCPStaticManagementFixture, self()},
        mcp_preflight: {MCPStaticManagementFixture, self()}
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    end)

    :ok
  end

  test "MCP inventory requires a session and never exposes a platform route" do
    assert build_conn() |> get("https://localhost" <> @path) |> json_response(401)
    assert (build_conn() |> get("https://localhost/api/platform/mcp-connections")).status == 404
    authenticated = login()
    conn = authenticated |> recycle() |> get("https://localhost" <> @path)
    assert json_response(conn, 200) == %{"connections" => []}
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "connect requires CSRF, validates before saving and returns no credentials" do
    authenticated = login()

    input = %{
      "endpoint" => "https://mcp.example.test/mcp",
      "auth_method" => "bearer",
      "credentials" => %{"token" => "synthetic-private"}
    }

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      authenticated
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", "invalid")
      |> post("https://localhost" <> @path, input)
    end

    refute_received {:mcp_checked, _}
    page = authenticated |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost" <> @path, input)

    body = json_response(conn, 201)
    assert body["connection"]["server_name"] == "Calendar"
    assert body["connection"]["tool_count"] == 0
    refute conn.resp_body =~ "synthetic-private"
    assert_receive {:mcp_checked, @tenant}
    assert_receive {:mcp_saved, @tenant, %{"token" => "synthetic-private"}}
  end

  test "request logs hide custom header credentials and endpoint query values" do
    authenticated = login()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn =
          authenticated
          |> recycle()
          |> post("https://localhost" <> @path, %{
            "endpoint" => "https://mcp.example.test/mcp?key=sensitive-url-marker",
            "auth_method" => "headers",
            "credentials" => %{
              "headers" => [%{"name" => "X-API-Key", "value" => "sensitive-header-marker"}]
            }
          })

        assert conn.status == 422
        refute conn.resp_body =~ "sensitive-url-marker"
      end)

    refute log =~ "sensitive-header-marker"
    refute log =~ "sensitive-url-marker"
  end

  test "preflight is tenant-only, session/CSRF protected and does not save" do
    path = "https://localhost/api/tenants/#{@tenant}/mcp-discovery"
    input = %{"endpoint" => "https://mcp.example.test/mcp", "revision" => "draft-1"}
    assert build_conn() |> post(path, input) |> json_response(401)

    assert (build_conn() |> post("https://localhost/api/platform/mcp-discovery", input)).status ==
             404

    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", "invalid")
      |> post(path, input)
    end

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, input)

    assert json_response(conn, 200)["discovery"]["revision"] == "draft-1"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert_receive {:mcp_preflight, @tenant}
    refute_received {:mcp_saved, _, _}
  end

  test "connection details return cached tools without credentials" do
    path = "https://localhost" <> @path <> "/connection-id"
    assert build_conn() |> get(path) |> json_response(401)
    conn = login() |> recycle() |> get(path)
    body = json_response(conn, 200)["connection"]
    assert body["tools"] == [%{"name" => "list_events"}]
    refute conn.resp_body =~ "hidden-secret"
    refute_received {:mcp_checked, _}
  end

  test "duplicate revoked endpoints return only the identity and generation needed for explicit reconnect" do
    conn =
      login()
      |> recycle()
      |> post("https://localhost" <> @path, %{
        "endpoint" => "https://mcp.example.test/revoked",
        "auth_method" => "bearer",
        "credentials" => %{"token" => "fresh-private"}
      })

    assert json_response(conn, 409) == %{
             "error" => %{
               "code" => "mcp_reconnect_required",
               "connection_id" => "revoked-connection",
               "generation" => 4
             }
           }

    refute conn.resp_body =~ "fresh-private"
    refute_received {:mcp_replaced, _, _, _, _}
  end

  test "explicit reconnect requires session, CSRF and the retained generation" do
    path = "https://localhost" <> @path <> "/revoked-connection/reconnect"

    input = %{
      "endpoint" => "https://mcp.example.test/revoked",
      "auth_method" => "bearer",
      "credentials" => %{"token" => "fresh-private"},
      "generation" => 4
    }

    assert build_conn() |> post(path, input) |> json_response(401)

    assert (build_conn()
            |> post(
              "https://localhost/api/platform/mcp-connections/revoked-connection/reconnect",
              input
            )).status == 404

    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", "invalid")
      |> post(path, input)
    end

    conn =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, input)

    public = json_response(conn, 200)["connection"]
    assert public["id"] == "revoked-connection"
    assert public["namespace"] == "stable"
    assert public["generation"] == 5
    refute conn.resp_body =~ "fresh-private"

    assert_receive {:mcp_replaced, @tenant, "revoked-connection", 4,
                    %{"token" => "fresh-private"}}

    refute_received {:mcp_resolved, _, _}

    stale =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> post(path, %{input | "generation" => 3})

    assert json_response(stale, 409)["error"]["code"] == "stale_mcp_connection"
    refute_received {:mcp_replaced, _, _, _, _}
  end

  test "static catalog refresh retains generation and never rewrites credentials" do
    conn =
      login()
      |> recycle()
      |> patch("https://localhost" <> @path <> "/connection-id", %{
        "generation" => 3,
        "refresh_tools" => true
      })

    public = json_response(conn, 200)["connection"]
    assert public["generation"] == 3
    assert public["tool_count"] == 0
    refute conn.resp_body =~ "hidden-secret"

    assert_receive {:mcp_catalog_saved, @tenant, "connection-id", 3,
                    %{server_name: "Calendar", catalog: []}}

    refute_received {:mcp_saved, _, _}
    refute_received {:mcp_replaced, _, _, _, _}
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
