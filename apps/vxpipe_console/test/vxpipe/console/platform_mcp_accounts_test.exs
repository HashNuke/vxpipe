defmodule Vxpipe.Console.PlatformMCPAccountsTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Calls.ApiKeyManagement
  alias Vxpipe.Console.Test.MCPOAuth
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount
  alias Vxpipe.Identity.{Bootstrap, Sessions}

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    CredentialStore,
    IdentityInstallationStore,
    IdentityRoleStore,
    Repo
  }

  alias Vxpipe.Persistence.Schema.{ApiKey, IdentityUser, UserAccessEvent}

  @endpoint Endpoint
  @version "2025-11-25"
  @password "local-account-password-15!"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    MCPOAuth.configure()
    original = Application.fetch_env!(:vxpipe_calls, Calls)
    mount = Endpoint.config(:gateway_mount)
    original_identity = Application.get_env(:vxpipe_identity, :dependencies)
    original_backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      Application.put_env(:vxpipe_calls, Calls, original)
      Phoenix.Config.put(Endpoint, :gateway_mount, mount)

      if original_identity,
        do: Application.put_env(:vxpipe_identity, :dependencies, original_identity),
        else: Application.delete_env(:vxpipe_identity, :dependencies)

      if original_backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, original_backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    Application.put_env(
      :vxpipe_calls,
      Calls,
      Keyword.merge(original,
        credential_repository: {CredentialStore, Repo},
        access_key_repository: {AccessKeyStore, Repo}
      )
    )

    Phoenix.Config.put(
      Endpoint,
      :gateway_mount,
      Mount.init(
        mcp: [
          enabled: true,
          issuer: "https://localhost",
          resource: MCPOAuth.resource(),
          allowed_hosts: ["localhost"]
        ],
        account_management: [
          enabled: true,
          browser_auth: {Vxpipe.Console.ProductAPIAuthentication, []}
        ]
      )
    )

    deps = %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: IdentityRoleStore,
      sessions: Vxpipe.Persistence.IdentitySessionStore,
      installations: IdentityInstallationStore,
      audit: Vxpipe.Persistence.IdentityAuditStore,
      attempts: Vxpipe.Persistence.IdentityAttemptStore,
      hasher: Vxpipe.Identity.Argon2Hasher
    }

    Application.put_env(:vxpipe_identity, :dependencies, deps)
    Application.put_env(:vxpipe_console, :user_identity_backend, Vxpipe.Console.UserIdentity)

    bootstrap =
      case Bootstrap.status(deps) do
        {:ok, :pending_first_run} ->
          Bootstrap.complete_first_run(deps, "accounts-root@example.test", @password, @password)

        {:ok, :pending_operator_proof} ->
          {:ok, %{proof: proof}} = IdentityInstallationStore.issue_setup_proof(900)

          Bootstrap.complete_with_proof(
            deps,
            proof,
            "accounts-root@example.test",
            @password,
            @password
          )
      end

    {:ok, %{user: root}} = bootstrap
    {:ok, %{token: token}} = Sessions.login(deps, root.email, @password, "local")
    {:ok, actor} = Sessions.authenticate(deps, token)
    {:ok, platform} = ApiKeyManagement.create(actor, "Account acceptance", "platform", nil, [])
    {:ok, tenant, tenant_key} = Calls.bootstrap_tenant("Account membership", [:admin, :calls])
    {:ok, role} = IdentityRoleStore.fetch_by_slug("tenant-manager")

    %{
      deps: deps,
      platform: platform,
      tenant: tenant,
      tenant_key: tenant_key,
      role: role,
      oauth: MCPOAuth.issue(actor),
      tenant_oauth: MCPOAuth.equivalent_to_api_key(tenant_key.secret)
    }
  end

  test "MCP create and HTTP partial updates preserve account state with distinct OAuth and key audit attribution",
       c do
    session = initialize(c.oauth.access_token)
    created = tool(c.oauth.access_token, session, 2, "create_user", create_params(c))
    assert created["isError"] == false
    user = created["structuredContent"]
    assert %{"user_id" => id, "role_id" => role, "enabled" => true} = user
    assert role == c.role.public_id
    assert user["memberships"] == [%{"tenant_key" => c.tenant.key, "access" => "read_write"}]
    refute Map.has_key?(user, "password_hash")
    {:ok, %{token: token}} = Sessions.login(c.deps, user["email"], @password, "local")

    disabled =
      http(c.platform.secret, :post, "/api/users/#{id}/disable", %{}) |> json_response(200)

    assert disabled["user"]["enabled"] == false
    assert {:error, _} = Sessions.authenticate(c.deps, token)
    assert {:error, _} = Sessions.login(c.deps, user["email"], @password, "local")

    changed =
      http(c.platform.secret, :patch, "/api/users/#{id}", %{email: "changed-account@example.test"})
      |> json_response(200)

    assert changed["user"] == %{
             "id" => id,
             "email" => "changed-account@example.test",
             "roleId" => role,
             "enabled" => false,
             "memberships" => [%{"tenantId" => c.tenant.key, "access" => "read_write"}]
           }

    enabled = tool(c.oauth.access_token, session, 3, "update_user", %{user_id: id, enabled: true})
    assert enabled["isError"] == false
    assert enabled["structuredContent"]["enabled"] == true
    assert {:error, _} = Sessions.authenticate(c.deps, token)
    assert {:ok, _} = Sessions.login(c.deps, "changed-account@example.test", @password, "local")

    browser =
      post(build_conn(), "https://localhost/auth/api/login", %{
        email: "changed-account@example.test",
        password: @password
      })

    assert browser.status == 200

    assert browser |> recycle() |> get("https://localhost/api/users") |> Map.fetch!(:status) ==
             403

    selected_key =
      browser
      |> recycle()
      |> put_req_header("authorization", "Bearer " <> c.platform.secret)
      |> get("https://localhost/api/users")

    assert selected_key.status == 200

    stored = Repo.get_by!(IdentityUser, public_id: id)
    key = Repo.get_by!(ApiKey, public_id: c.platform.key.id)

    events =
      Repo.all(
        from(e in UserAccessEvent,
          where: e.target_user_id == ^stored.id and e.action in ["user_created", "user_updated"]
        )
      )

    assert length(events) == 4
    oauth_events = Enum.filter(events, &(&1.actor_oauth_grant_public_id == c.oauth.grant_id))
    key_events = Enum.filter(events, &(&1.actor_api_key_id == key.id))
    assert length(oauth_events) == 2
    assert length(key_events) == 2
    actor = Repo.get_by!(IdentityUser, public_id: c.oauth.principal.user_public_id)

    assert Enum.all?(
             oauth_events,
             &(&1.actor_user_id == actor.id and is_nil(&1.actor_api_key_id))
           )

    assert Enum.all?(
             key_events,
             &(is_nil(&1.actor_user_id) and is_nil(&1.actor_oauth_grant_public_id))
           )

    refute inspect(events) =~ @password
  end

  test "safe account directories share bounded pages and role options across transports", c do
    session = initialize(c.oauth.access_token)

    created =
      tool(c.oauth.access_token, session, 2, "create_user", create_params(c))["structuredContent"]

    path = "/api/users?query=created-account&role_id=#{c.role.public_id}&page_size=1"
    response = http(c.platform.secret, :get, path)
    assert get_resp_header(response, "cache-control") == ["no-store"]
    http_page = json_response(response, 200)

    mcp_page =
      tool(c.oauth.access_token, session, 3, "list_users", %{
        query: "created-account",
        role_id: c.role.public_id,
        page_size: 1
      })["structuredContent"]

    assert mcp_page["pagination"] == http_page["pagination"]
    assert mcp_page["items"] == [created]
    assert http_page["users"] == [http_user(created)]

    assert http_page["pagination"] == %{
             "page" => 1,
             "page_size" => 1,
             "total" => 1,
             "total_pages" => 1
           }

    assert http(c.platform.secret, :get, "/api/users/#{created["user_id"]}") |> json_response(200) ==
             %{"user" => http_user(created)}

    empty =
      tool(c.oauth.access_token, session, 4, "list_users", %{query: "absent-account"})[
        "structuredContent"
      ]

    assert empty["items"] == [] and empty["pagination"]["total_pages"] == 0
    assert http(c.platform.secret, :get, path <> "&page=2").status == 422

    assert tool(c.oauth.access_token, session, 5, "list_users", %{
             query: "created-account",
             page_size: 1,
             page: 2
           })["isError"] == true

    assert http(c.platform.secret, :get, "/api/users?page_size=51").status == 422

    roles = http(c.platform.secret, :get, "/api/role-options?page_size=2") |> json_response(200)

    mcp_roles =
      tool(c.oauth.access_token, session, 6, "list_role_options", %{page_size: 2})[
        "structuredContent"
      ]

    assert length(roles["roles"]) == 2
    assert mcp_roles["pagination"] == roles["pagination"]

    assert Enum.map(mcp_roles["items"], fn role ->
             %{"id" => role["role_id"], "name" => role["name"], "kind" => role["kind"]}
           end) == roles["roles"]

    assert Enum.all?(roles["roles"], &(Enum.sort(Map.keys(&1)) == ["id", "kind", "name"]))
    refute JSON.encode!(mcp_page) =~ "password"
  end

  test "tenant authority cannot manage accounts and key versus OAuth revocation remains separate",
       c do
    assert request(c.platform.secret, nil, "ping", 1, %{}).status == 401
    assert request(c.tenant_key.secret, nil, "ping", 1, %{}).status == 401
    assert http(c.oauth.access_token, :get, "/api/users").status == 401
    tenant_session = initialize(c.tenant_oauth.access_token)

    catalog =
      request(c.tenant_oauth.access_token, tenant_session, "tools/list", 2, %{})
      |> json_response(200)

    names = Enum.map(catalog["result"]["tools"], & &1["name"])

    refute Enum.any?(
             names,
             &(&1 in [
                 "list_users",
                 "create_user",
                 "update_user",
                 "disable_user",
                 "list_role_options"
               ])
           )

    assert http(c.tenant_key.secret, :get, "/api/users").status == 403
    assert http(c.tenant_key.secret, :post, "/api/users", create_params(c)).status == 403

    assert request(c.tenant_oauth.access_token, tenant_session, "tools/call", 3, %{
             name: "create_user",
             arguments: create_params(c)
           }).status == 403

    refute Repo.get_by(IdentityUser, normalized_email: "created-account@example.test")

    session = initialize(c.oauth.access_token)
    assert http(c.platform.secret, :get, "/api/users").status == 200
    assert :ok = AccessKeyStore.revoke(Repo, c.platform.key.id, DateTime.utc_now())
    assert http(c.platform.secret, :get, "/api/users").status == 401
    assert request(c.oauth.access_token, session, "ping", 3, %{}).status == 200
    assert :ok = MCPOAuth.revoke(c.oauth)

    assert request(c.oauth.access_token, session, "tools/call", 2, %{
             name: "list_users",
             arguments: %{}
           }).status == 401
  end

  test "transport schemas reject null booleans, password updates and authority fields without echoing secrets",
       c do
    session = initialize(c.oauth.access_token)

    user =
      tool(c.oauth.access_token, session, 2, "create_user", create_params(c))["structuredContent"]

    id = user["user_id"]

    for {changes, index} <-
          Enum.with_index(
            [
              %{"enabled" => "true"},
              %{"enabled" => nil},
              %{"password" => "private-password-sentinel"},
              %{"actor_api_key_public_id" => c.platform.key.id},
              %{"tenant_id" => 1}
            ],
            3
          ) do
      http = http(c.platform.secret, :patch, "/api/users/#{id}", changes)
      assert http.status == 422
      refute http.resp_body =~ "private-password-sentinel"

      mcp =
        request(c.oauth.access_token, session, "tools/call", index, %{
          name: "update_user",
          arguments: Map.put(changes, "user_id", id)
        })

      assert mcp.status == 400
      assert json_response(mcp, 400)["error"]["code"] == -32602
      refute mcp.resp_body =~ "private-password-sentinel"
    end

    assert {:ok, _} = Sessions.login(c.deps, user["email"], @password, "local")

    assert http(c.platform.secret, :get, "/api/users/#{id}") |> json_response(200) == %{
             "user" => http_user(user)
           }
  end

  defp http_user(user),
    do: %{
      "id" => user["user_id"],
      "email" => user["email"],
      "roleId" => user["role_id"],
      "enabled" => user["enabled"],
      "memberships" =>
        Enum.map(
          user["memberships"],
          &%{"tenantId" => &1["tenant_key"], "access" => &1["access"]}
        )
    }

  defp create_params(c),
    do: %{
      email: "created-account@example.test",
      password: @password,
      password_confirmation: @password,
      role_id: c.role.public_id,
      memberships: [%{tenant_key: c.tenant.key, access: "read_write"}]
    }

  defp http(secret, method, path, body \\ %{}) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> put_req_header("content-type", "application/json")

    dispatch(conn, Endpoint, method, "https://localhost" <> path, JSON.encode!(body))
  end

  defp initialize(secret) do
    conn =
      request(secret, nil, "initialize", 1, %{
        protocolVersion: @version,
        capabilities: %{},
        clientInfo: %{name: "account-acceptance", version: "1"}
      })

    assert conn.status == 200
    [session] = get_resp_header(conn, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  defp tool(secret, session, id, name, arguments),
    do:
      request(secret, session, "tools/call", id, %{name: name, arguments: arguments})
      |> json_response(200)
      |> Map.fetch!("result")

  defp request(secret, session, method, id, params) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", @version)

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn

    post(
      conn,
      "https://localhost/mcp",
      JSON.encode!(%{jsonrpc: "2.0", method: method, id: id, params: params})
    )
  end
end
