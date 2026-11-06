defmodule Vxpipe.Console.IntegrationsEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest

  alias Vxpipe.Console.Test.{FakeUserIdentity, OperatorCredentialRepository}
  @endpoint Vxpipe.Console.Endpoint
  @tenant "AAAAAAAAAAAAAAAA"

  setup do
    previous_identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    previous_calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    directory = {:ok, %{tenant: %{key: @tenant, name: "Tenant"}, bindings: []}}

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.merge(previous_calls,
        provider_credential_repository: {OperatorCredentialRepository, {self(), directory}},
        credential_repository: {Vxpipe.Console.Test.MCPManagementFixture, self()},
        mcp_connection_repository: {Vxpipe.Console.Test.MCPManagementFixture, self()}
      )
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, previous_identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, previous_calls)
    end)

    :ok
  end

  test "Connected integrations is an authenticated private inventory with the actual build version" do
    path = "/api/tenants/#{@tenant}/integrations?category=connected"
    assert build_conn() |> get("https://localhost" <> path) |> json_response(401)

    conn =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost" <> path)

    body = json_response(conn, 200)
    assert body["installation_version"] == Application.spec(:vxpipe_console, :vsn) |> to_string()
    assert body["directory_status"] == "local"
    assert body["local_items"] == []
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "category endpoints require a session and category page URLs survive reload" do
    settings = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    tenant = %Vxpipe.Calls.Tenant{
      key: @tenant,
      name: "Tenant",
      inserted_at: ~U[2026-11-06 00:00:00Z]
    }

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(
        settings,
        :admin_repository,
        {Vxpipe.Console.Test.NavigationRepository, {self(), [tenant], {:ok, []}}}
      )
    )

    assert build_conn()
           |> get("https://localhost/api/tenants/#{@tenant}/integrations/categories")
           |> json_response(401)

    authenticated =
      post(build_conn(), "https://localhost/auth/api/login", %{
        "email" => FakeUserIdentity.email(),
        "password" => FakeUserIdentity.password()
      })

    for path <- ["/platform/services/ai", "/t/#{@tenant}/services/calendar"] do
      assert authenticated |> recycle() |> get("https://localhost" <> path) |> html_response(200)
    end
  end
end
