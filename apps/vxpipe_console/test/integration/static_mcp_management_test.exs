defmodule Vxpipe.Console.StaticMCPManagementTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn, only: [put_req_header: 3]
  alias Vxpipe.Calls.Administration
  alias Vxpipe.Console.Test.FakeUserIdentity
  alias Vxpipe.MCP.{CheckHTTPFixture, ConnectionCheck}
  alias Vxpipe.Persistence.{CredentialKeyring, CredentialStore, Repo}
  alias Vxpipe.Persistence.MCP.ConnectionStore
  alias Vxpipe.Persistence.Schema.MCPConnection

  @endpoint Vxpipe.Console.Endpoint
  @moduletag :integration
  @url "https://mcp.example.test/mcp"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    {:ok, keys} = CredentialKeyring.new("old", %{"old" => :crypto.strong_rand_bytes(32)})
    context = [repo: Repo, keyring: keys]
    server = start_supervised!({CheckHTTPFixture, owner: self()})
    local = CheckHTTPFixture.endpoint(server)

    check = fn tenant, configuration ->
      ConnectionCheck.run_loopback_test(tenant, %{configuration | endpoint: local})
    end

    options = [
      credential_repository: {CredentialStore, Repo},
      mcp_connection_repository: {ConnectionStore, context},
      mcp_connection_probe: {Vxpipe.Console.MCPConnectionProbe, [connection_check: check]}
    ]

    {:ok, tenant, _} = Administration.bootstrap_tenant("Static MCP acceptance", [:admin], options)
    {:ok, other, _} = Administration.bootstrap_tenant("Other tenant", [:admin], options)
    identity = Application.get_env(:vxpipe_console, :user_identity_backend)
    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)
    Application.put_env(:vxpipe_console, :user_identity_backend, FakeUserIdentity)
    Application.put_env(:vxpipe_calls, Vxpipe.Calls, Keyword.merge(calls, options))

    on_exit(fn ->
      Application.put_env(:vxpipe_console, :user_identity_backend, identity)
      Application.put_env(:vxpipe_calls, Vxpipe.Calls, calls)
    end)

    page =
      build_conn()
      |> post("https://localhost/auth/api/login", %{
        email: FakeUserIdentity.email(),
        password: FakeUserIdentity.password()
      })
      |> recycle()
      |> get("https://localhost/account")

    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)
    %{tenant: tenant.key, other: other.key, context: context, page: page, csrf: csrf}
  end

  test "HTTP disconnect and explicit reconnect preserve the durable identity with fresh wire credentials",
       data do
    created =
      request(data, :post, "", input("first-private"))
      |> json_response(201)
      |> Map.fetch!("connection")

    id = created["id"]
    assert_header("first-private")
    assert request(%{data | tenant: data.other}, :get, "/" <> id, %{}) |> json_response(404)

    revoked =
      request(data, :delete, "/" <> id, %{"generation" => 1})
      |> json_response(200)
      |> Map.fetch!("connection")

    assert revoked["generation"] == 2
    record = Repo.get_by!(MCPConnection, public_id: id)
    assert record.encrypted_payload == nil
    assert record.encryption_key_id == nil
    assert request(data, :get, "", %{}) |> json_response(200) == %{"connections" => []}
    assert request(data, :get, "/" <> id, %{}) |> json_response(404)

    proposal =
      request(data, :post, "", input("proposal-private"))
      |> json_response(409)
      |> Map.fetch!("error")

    assert proposal == %{
             "code" => "mcp_reconnect_required",
             "connection_id" => id,
             "generation" => 2
           }

    refute_received {:check_http, "initialize", _}
    assert Repo.get_by!(MCPConnection, public_id: id).status == "revoked"
    path = "/" <> id <> "/reconnect"
    body = Map.put(input("fresh-private"), "generation", 2)
    restored = request(data, :post, path, body) |> json_response(200) |> Map.fetch!("connection")
    assert_header("fresh-private")
    assert restored["id"] == id
    assert restored["namespace"] == created["namespace"]
    assert restored["generation"] == 3
    refute JSON.encode!(restored) =~ "private"
    assert {:ok, resolved} = ConnectionStore.resolve(data.context, data.tenant, id)
    assert resolved.secrets == %{"token" => "fresh-private"}

    assert request(data, :post, path, body) |> json_response(409) |> get_in(["error", "code"]) ==
             "stale_mcp_connection"
  end

  test "fresh HTTP replacement repairs a record whose old encryption key is unavailable", data do
    created =
      request(data, :post, "", input("first-private"))
      |> json_response(201)
      |> Map.fetch!("connection")

    id = created["id"]
    assert_header("first-private")
    {:ok, keys} = CredentialKeyring.new("new", %{"new" => :crypto.strong_rand_bytes(32)})
    context = Keyword.put(data.context, :keyring, keys)
    calls = Application.fetch_env!(:vxpipe_calls, Vxpipe.Calls)

    Application.put_env(
      :vxpipe_calls,
      Vxpipe.Calls,
      Keyword.put(calls, :mcp_connection_repository, {ConnectionStore, context})
    )

    assert {:error, _} = ConnectionStore.resolve(context, data.tenant, id)
    omitted = %{"endpoint" => @url, "auth_method" => "bearer", "generation" => 1}
    assert request(data, :patch, "/" <> id, omitted) |> json_response(503)
    refute_received {:check_http, "initialize", _}

    public =
      request(data, :patch, "/" <> id, Map.put(input("replacement-private"), "generation", 1))
      |> json_response(200)
      |> Map.fetch!("connection")

    assert_header("replacement-private")
    assert public["generation"] == 2
    assert {:ok, resolved} = ConnectionStore.resolve(context, data.tenant, id)
    assert resolved.secrets == %{"token" => "replacement-private"}
    refute JSON.encode!(public) =~ "private"
  end

  defp input(token),
    do: %{"endpoint" => @url, "auth_method" => "bearer", "credentials" => %{"token" => token}}

  defp request(data, method, suffix, body) do
    conn =
      data.page
      |> recycle()
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)
      |> put_req_header("x-csrf-token", data.csrf)

    dispatch(
      conn,
      @endpoint,
      method,
      "https://localhost/api/tenants/#{data.tenant}/mcp-connections" <> suffix,
      body
    )
  end

  defp assert_header(token) do
    assert_receive {:check_http, "initialize", headers}
    assert List.keyfind(headers, "authorization", 0) == {"authorization", "Bearer " <> token}
  end
end
