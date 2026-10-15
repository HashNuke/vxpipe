defmodule Vxpipe.Console.PlatformMCPEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Persistence.{CredentialStore, Repo}

  @endpoint Endpoint
  @version "2025-11-25"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    original = Application.fetch_env!(:vxpipe_calls, Calls)
    mount = Endpoint.config(:gateway_mount)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Calls, original)
      Phoenix.Config.put(Endpoint, :gateway_mount, mount)
    end)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.put(original, :credential_repository, {CredentialStore, Repo})
    )

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Mount.init(mcp: [enabled: true, allowed_hosts: ["localhost"]])
    )

    {:ok, tenant, key} = Calls.bootstrap_tenant("MCP endpoint fixture", [:calls])
    %{tenant: tenant, key: key}
  end

  test "Console serves key-bound MCP sessions and rechecks persisted revocation", data do
    initialized = request(data.key.secret, "initialize", 1, nil, initialize_params())
    assert json_response(initialized, 200)["result"]["protocolVersion"] == @version
    assert [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

    catalog = request(data.key.secret, "tools/list", 2, session)
    assert json_response(catalog, 200)["result"]["tools"] == []
    assert get_resp_header(catalog, "cache-control") == ["no-store"]

    {:ok, other} = Calls.issue_api_key(data.tenant.key, "other key", [:calls])
    assert request(other.secret, "ping", 3, session).status == 404

    {:ok, _revoked} = Calls.revoke_api_key(data.tenant.key, data.key.id)
    assert request(data.key.secret, "ping", 4, session).status == 401
  end

  test "Console does not substitute a browser session or parse unauthenticated MCP JSON" do
    response =
      build_conn()
      |> Plug.Test.init_test_session(%{"vxpipe_user_session" => String.duplicate("x", 43)})
      |> put_req_header("content-type", "application/json")
      |> post("https://localhost/mcp", "invalid-json")

    assert response.status == 401
    assert get_resp_header(response, "www-authenticate") == ["Bearer realm=\"vxpipe\""]
  end

  defp request(secret, method, id, session, params \\ %{}) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-protocol-version", @version)

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn

    post(
      conn,
      "https://localhost/mcp",
      JSON.encode!(%{jsonrpc: "2.0", id: id, method: method, params: params})
    )
  end

  defp initialize_params do
    %{
      protocolVersion: @version,
      capabilities: %{},
      clientInfo: %{name: "vxpipe-local-client", version: "1"}
    }
  end
end
