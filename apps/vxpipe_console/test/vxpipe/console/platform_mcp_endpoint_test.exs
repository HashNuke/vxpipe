defmodule Vxpipe.Console.PlatformMCPEndpointTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Calls.ApiKeyManagement
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Persistence.{AccessKeyStore, AdminStore, CredentialStore, Repo}

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
      Keyword.merge(original,
        credential_repository: {CredentialStore, Repo},
        access_key_repository: {AccessKeyStore, Repo},
        admin_repository: {AdminStore, Repo}
      )
    )

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Mount.init(
        mcp: [enabled: true, allowed_hosts: ["localhost"]],
        tenant_directory: [enabled: true]
      )
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

    assert Enum.map(json_response(catalog, 200)["result"]["tools"], & &1["name"]) ==
             ["list_tenants", "get_tenant"]

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

  test "HTTP and MCP agree on scoped directory pages and foreign lookup errors", data do
    others =
      for key <- ["MCPFIXTURE000003", "MCPFIXTURE000001", "MCPFIXTURE000002"] do
        {:ok, tenant, _key} =
          Calls.bootstrap_tenant("Same name", [:calls], tenant_key_generator: fn -> key end)

        tenant
      end

    {:ok, full} = Calls.issue_api_key(data.tenant.key, "Full tenant fixture", [:admin, :calls])
    grants = Vxpipe.Identity.Permission.builtin_grants(:superadmin)

    administrator = %Vxpipe.Identity.Principal{
      user_public_id: "fixture",
      session_public_id: "fixture",
      account_kind: :superadmin,
      grants: grants,
      assigned_tenants: %{},
      all_tenant_actions: grants
    }

    {:ok, platform} =
      ApiKeyManagement.create(administrator, "Platform fixture", "platform", nil, [])

    # The local test database may contain bootstrap fixtures outside this sandbox.
    # Include that baseline rather than assuming an empty installation directory.
    platform_tenants = Repo.all(Vxpipe.Persistence.Schema.Tenant)

    for secret <- [data.key.secret, full.secret, platform.secret] do
      initialized = request(secret, "initialize", 1, nil, initialize_params())
      [session] = get_resp_header(initialized, "mcp-session-id")
      on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
      expected = if secret == platform.secret, do: platform_tenants, else: [data.tenant]

      expected_keys = Enum.map(expected, & &1.key)

      pages = div(length(expected) + 1, 2)

      returned_keys =
        for page <- 1..pages, reduce: [] do
          keys ->
            http = rest(secret, "/api/tenants?page=#{page}&page_size=2") |> json_response(200)
            mcp = tool(secret, session, page + 1, "list_tenants", %{page: page, page_size: 2})
            assert mcp["structuredContent"] == http
            assert http["pagination"]["total"] == length(expected)
            assert http["pagination"]["total_pages"] == pages
            keys ++ Enum.map(http["items"], & &1["tenant_key"])
        end

      assert Enum.sort(returned_keys) == Enum.sort(expected_keys)

      if secret == platform.secret do
        duplicate_name_keys = Enum.map(others, & &1.key)

        assert Enum.filter(returned_keys, &(&1 in duplicate_name_keys)) ==
                 Enum.sort(duplicate_name_keys)
      end

      out_of_range =
        rest(secret, "/api/tenants?page=#{pages + 1}&page_size=2") |> json_response(422)

      mcp = tool(secret, session, pages + 2, "list_tenants", %{page: pages + 1, page_size: 2})
      assert mcp["isError"] == true
      assert mcp["structuredContent"] == out_of_range

      detail = rest(secret, "/api/tenants/#{data.tenant.key}") |> json_response(200)

      assert tool(secret, session, pages + 3, "get_tenant", %{tenant_key: data.tenant.key})[
               "structuredContent"
             ] == detail

      if secret != platform.secret do
        foreign = hd(others).key
        error = rest(secret, "/api/tenants/#{foreign}") |> json_response(404)

        assert tool(secret, session, pages + 4, "get_tenant", %{tenant_key: foreign})[
                 "structuredContent"
               ] == error
      end
    end
  end

  test "HTTP and MCP agree on an empty directory without inventing a page", data do
    configured = Application.fetch_env!(:vxpipe_calls, Calls)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.put(configured, :admin_repository, {__MODULE__, :empty})
    )

    initialized = request(data.key.secret, "initialize", 1, nil, initialize_params())
    [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

    http = rest(data.key.secret, "/api/tenants") |> json_response(200)

    assert http == %{
             "items" => [],
             "pagination" => %{
               "page" => 1,
               "page_size" => 25,
               "total" => 0,
               "total_pages" => 0
             }
           }

    assert tool(data.key.secret, session, 2, "list_tenants", %{})["structuredContent"] == http

    error = rest(data.key.secret, "/api/tenants?page=2") |> json_response(422)

    assert tool(data.key.secret, session, 3, "list_tenants", %{page: 2})["structuredContent"] ==
             error
  end

  def search_tenants(:empty, _scope, _query, _limit, _offset), do: {:ok, {[], 0}}

  defp rest(secret, path),
    do:
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> get("https://localhost" <> path)

  defp tool(secret, session, id, name, arguments) do
    request(secret, "tools/call", id, session, %{name: name, arguments: arguments})
    |> json_response(200)
    |> Map.fetch!("result")
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
