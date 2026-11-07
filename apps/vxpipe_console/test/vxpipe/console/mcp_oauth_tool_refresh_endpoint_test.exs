defmodule Vxpipe.Console.MCPOAuthToolRefreshEndpointTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
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

  test "existing detail and update routes support OAuth labels and credentialless tool refresh" do
    path = "https://localhost" <> @path <> "/oauth-connection"
    page = login() |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    details = page |> recycle() |> get(path) |> json_response(200)
    assert details["connection"]["oauth"]["registration_method"] == "dcr"

    response =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> patch(path, %{"generation" => 7, "refresh_tools" => true})

    assert json_response(response, 200)["connection"]["generation"] == 7
    assert_receive {:mcp_checked, @tenant}
    assert_receive {:mcp_catalog_saved, @tenant, "oauth-connection", 7, %{catalog: []}}
    refute response.resp_body =~ "private"

    invalid =
      page
      |> recycle()
      |> enforce_csrf()
      |> put_req_header("x-csrf-token", csrf)
      |> patch(path, %{"generation" => 7, "refresh_tools" => true, "credentials" => %{}})

    assert json_response(invalid, 422)["error"]["code"] == "invalid_mcp_configuration"
    refute_received {:mcp_checked, _}
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
