defmodule Vxpipe.Console.PlatformMCPEndpointTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Plug.Conn

  alias Vxpipe.Calls
  alias Vxpipe.Calls.ApiKeyManagement
  alias Vxpipe.Console.Test.MCPOAuth
  alias Vxpipe.Console.Endpoint
  alias Vxpipe.Gateway.HTTP.Mount

  alias Vxpipe.Persistence.{
    AccessKeyStore,
    AdminStore,
    CallSpecStore,
    CallStore,
    CredentialStore,
    Repo
  }

  @endpoint Endpoint
  @version "2025-11-25"

  setup do
    if is_nil(Process.whereis(Repo)), do: start_supervised!(Repo)
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    MCPOAuth.configure()
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
        admin_repository: {AdminStore, Repo},
        call_spec_repository: {CallSpecStore, Repo},
        call_repository: {CallStore, Repo},
        registries: %{host_tools: %{}}
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
        call_admission: [
          enabled: true,
          browser_auth: {Vxpipe.Console.ProductAPIAuthentication, []}
        ],
        tenant_directory: [enabled: true],
        call_spec_reads: [enabled: true],
        call_spec_authoring: [enabled: true]
      )
    )

    {:ok, tenant, key} = Calls.bootstrap_tenant("MCP endpoint fixture", [:calls])
    %{tenant: tenant, key: key, oauth: MCPOAuth.equivalent_to_api_key(key.secret)}
  end

  test "Console serves grant-bound MCP sessions across refresh and persisted revocation", data do
    initialized = request(data.oauth.access_token, "initialize", 1, nil, initialize_params())
    assert json_response(initialized, 200)["result"]["protocolVersion"] == @version
    assert [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

    catalog = request(data.oauth.access_token, "tools/list", 2, session)

    assert Enum.map(json_response(catalog, 200)["result"]["tools"], & &1["name"]) ==
             ["list_tenants", "get_tenant", "create_call", "create_join_token", "hangup_call"]

    assert get_resp_header(catalog, "cache-control") == ["no-store"]

    other = MCPOAuth.equivalent_to_api_key(data.key.secret)
    assert request(other.access_token, "ping", 3, session).status == 404
    {:ok, refreshed} = MCPOAuth.refresh(data.oauth)
    assert request(refreshed.access_token, "ping", 4, session).status == 200
    assert request(data.key.secret, "ping", 5, session).status == 401
    assert rest(data.key.secret, "/api/tenants").status == 200
    assert :ok = MCPOAuth.revoke(data.oauth)
    assert request(refreshed.access_token, "ping", 6, session).status == 401
  end

  test "Console does not substitute a browser session or parse unauthenticated MCP JSON" do
    response =
      build_conn()
      |> Plug.Test.init_test_session(%{"vxpipe_user_session" => String.duplicate("x", 43)})
      |> put_req_header("content-type", "application/json")
      |> post("https://localhost/mcp", "invalid-json")

    assert response.status == 401

    assert get_resp_header(response, "www-authenticate") == [
             ~s(Bearer realm="vxpipe", resource_metadata="https://localhost/.well-known/oauth-protected-resource/mcp", scope="mcp")
           ]
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
      oauth = MCPOAuth.equivalent_to_api_key(secret)
      initialized = request(oauth.access_token, "initialize", 1, nil, initialize_params())
      [session] = get_resp_header(initialized, "mcp-session-id")
      on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
      expected = if secret == platform.secret, do: platform_tenants, else: [data.tenant]

      expected_keys = Enum.map(expected, & &1.key)

      pages = div(length(expected) + 1, 2)

      returned_keys =
        for page <- 1..pages, reduce: [] do
          keys ->
            http = rest(secret, "/api/tenants?page=#{page}&page_size=2") |> json_response(200)

            mcp =
              tool(oauth.access_token, session, page + 1, "list_tenants", %{
                page: page,
                page_size: 2
              })

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

      mcp =
        tool(oauth.access_token, session, pages + 2, "list_tenants", %{
          page: pages + 1,
          page_size: 2
        })

      assert mcp["isError"] == true
      assert mcp["structuredContent"] == out_of_range

      detail = rest(secret, "/api/tenants/#{data.tenant.key}") |> json_response(200)

      assert tool(oauth.access_token, session, pages + 3, "get_tenant", %{
               tenant_key: data.tenant.key
             })[
               "structuredContent"
             ] == detail

      if secret != platform.secret do
        foreign = hd(others).key
        error = rest(secret, "/api/tenants/#{foreign}") |> json_response(404)

        assert tool(oauth.access_token, session, pages + 4, "get_tenant", %{tenant_key: foreign})[
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

    initialized = request(data.oauth.access_token, "initialize", 1, nil, initialize_params())
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

    assert tool(data.oauth.access_token, session, 2, "list_tenants", %{})["structuredContent"] ==
             http

    error = rest(data.key.secret, "/api/tenants?page=2") |> json_response(422)

    assert tool(data.oauth.access_token, session, 3, "list_tenants", %{page: 2})[
             "structuredContent"
           ] ==
             error
  end

  test "persisted full tenant and platform keys share source revisions across HTTP and MCP",
       data do
    {:ok, full} = Calls.issue_api_key(data.tenant.key, "Spec author", [:admin])
    grants = Vxpipe.Identity.Permission.builtin_grants(:superadmin)

    administrator = %Vxpipe.Identity.Principal{
      user_public_id: "fixture",
      session_public_id: "fixture",
      account_kind: :superadmin,
      grants: grants,
      assigned_tenants: %{},
      all_tenant_actions: grants
    }

    {:ok, platform} = ApiKeyManagement.create(administrator, "Spec platform", "platform", nil, [])
    {:ok, foreign, _} = Calls.bootstrap_tenant("Foreign spec", [:admin])
    {:ok, foreign_spec} = Calls.save_call_spec(foreign.key, spec_source())
    base = "/api/tenants/#{data.tenant.key}/call-specs"

    for secret <- [full.secret, platform.secret] do
      oauth = MCPOAuth.equivalent_to_api_key(secret)
      initialized = request(oauth.access_token, "initialize", 1, nil, initialize_params())
      [session] = get_resp_header(initialized, "mcp-session-id")
      on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

      created =
        tool(oauth.access_token, session, 2, "create_call_spec", %{
          tenant_key: data.tenant.key,
          call_spec_definition: spec_source()
        })

      assert created["isError"] == false
      id = created["structuredContent"]["call_spec_id"]
      assert created["structuredContent"]["validation_errors"] == []
      source = Map.put(spec_source(), "name", "Second revision")

      updated =
        rest_write(secret, :put, base <> "/" <> id, %{source: source}) |> json_response(201)

      assert updated["call_spec"]["revision"] == 2

      read = rest(secret, base <> "/" <> id) |> json_response(200) |> Map.fetch!("call_spec")

      mcp =
        tool(oauth.access_token, session, 3, "get_call_spec", %{
          tenant_key: data.tenant.key,
          call_spec_id: id
        })[
          "structuredContent"
        ]

      assert mcp ==
               read
               |> Map.take(~w(call_spec_id revision latest_revision published_revision))
               |> Map.put("call_spec_definition", read["source"])

      assert mcp["call_spec_definition"] == source
      assert mcp["published_revision"] == nil

      publication =
        tool(oauth.access_token, session, 4, "publish_call_spec_revision", %{
          tenant_key: data.tenant.key,
          call_spec_id: id,
          revision: 1
        })

      assert publication["structuredContent"] == %{
               "call_spec_id" => id,
               "published_revision" => 1
             }

      historical = rest(secret, base <> "/" <> id <> "?revision=1") |> json_response(200)
      assert historical["call_spec"]["source"] == spec_source()
      assert historical["call_spec"]["latest_revision"] == 2
      assert historical["call_spec"]["published_revision"] == 1

      listed = rest(secret, base) |> json_response(200)

      mcp_list =
        tool(oauth.access_token, session, 5, "list_call_specs", %{tenant_key: data.tenant.key})[
          "structuredContent"
        ]

      assert mcp_list["pagination"] == listed["pagination"]

      assert Enum.map(mcp_list["items"], & &1["call_spec_id"]) ==
               Enum.map(listed["call_specs"], & &1["id"])

      for name <- ["get_call_spec", "update_call_spec"] do
        args = %{tenant_key: data.tenant.key, call_spec_id: foreign_spec.call_spec_id}

        args =
          if name == "update_call_spec",
            do: Map.put(args, :call_spec_definition, source),
            else: args

        denied =
          tool(
            oauth.access_token,
            session,
            if(name == "get_call_spec", do: 6, else: 7),
            name,
            args
          )

        assert denied["isError"] == true
        assert denied["structuredContent"]["error"]["code"] == "call_spec_not_found"
      end

      assert rest(secret, base <> "/" <> foreign_spec.call_spec_id).status == 404

      assert rest_write(secret, :put, base <> "/" <> foreign_spec.call_spec_id, %{source: source}).status ==
               404
    end

    initialized = request(data.oauth.access_token, "initialize", 1, nil, initialize_params())
    [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    assert rest(data.key.secret, base).status == 403

    assert request(data.oauth.access_token, "tools/call", 2, session, %{
             name: "list_call_specs",
             arguments: %{tenant_key: data.tenant.key}
           }).status == 403
  end

  test "persisted call creation and pinned single-use tokens agree across HTTP and MCP", data do
    {:ok, full} = Calls.issue_api_key(data.tenant.key, "Full call fixture", [:admin, :calls])
    administrator = Vxpipe.Console.Test.FakeUserIdentity.principal()

    {:ok, platform} =
      ApiKeyManagement.create(administrator, "Platform call fixture", "platform", nil, [])

    {:ok, foreign, _} = Calls.bootstrap_tenant("Foreign call fixture", [:calls])

    source =
      Map.put(spec_source(), "call_variables", %{
        "sections" => %{
          "order" => %{
            "schema" => %{"type" => "object", "properties" => %{"id" => %{"type" => "string"}}}
          }
        }
      })

    variables = %{"order" => %{"id" => "local-order"}}
    {:ok, draft} = Calls.save_call_spec(data.tenant.key, source)

    {:ok, _published} =
      Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, draft.revision)

    creation_path = "/api/tenants/#{data.tenant.key}/call-specs/#{draft.call_spec_id}/calls"

    for {secret, index} <- Enum.with_index([data.key.secret, full.secret, platform.secret], 1) do
      oauth = MCPOAuth.equivalent_to_api_key(secret)
      session = session(oauth.access_token)
      key = "cross-transport-#{index}"

      created =
        tool(oauth.access_token, session, 2, "create_call", %{
          tenant_key: data.tenant.key,
          call_spec_id: draft.call_spec_id,
          variables: variables,
          idempotency_key: key
        })

      assert created["isError"] == false
      assert %{"call_id" => call_id} = created["structuredContent"]
      assert map_size(created["structuredContent"]) == 1

      replay =
        rest_write(secret, :post, creation_path, %{variables: variables}, [
          {"idempotency-key", key}
        ])

      assert get_resp_header(replay, "cache-control") == ["no-store"]

      assert %{"call" => %{"id" => ^call_id, "state" => "prepared", "revision" => 1}} =
               json_response(replay, 200)

      assert Repo.aggregate(
               from(c in Vxpipe.Persistence.Schema.Call, where: c.public_id == ^call_id),
               :count
             ) == 1

      assert {:ok, stored} = Calls.fetch_call(data.tenant.key, call_id)
      assert stored.initial_variables == variables

      tokens_path = "/api/tenants/#{data.tenant.key}/calls/#{call_id}/join-tokens"
      http = rest_write(secret, :post, tokens_path, %{}) |> json_response(201)

      mcp =
        tool(oauth.access_token, session, 3, "create_join_token", %{
          tenant_key: data.tenant.key,
          call_id: call_id
        })

      assert mcp["isError"] == false
      issued = mcp["structuredContent"]
      participant = http["participant_key"]

      assert Map.take(issued, ["call_id", "participant_key"]) ==
               Map.take(http, ["call_id", "participant_key"])

      assert {:ok, _, _} = DateTime.from_iso8601(issued["expires_at"])
      refute issued["token"] == http["join_token"]["token"]

      explicit_path =
        "/api/tenants/#{data.tenant.key}/calls/#{call_id}/participants/#{participant}/join-tokens"

      explicit = rest_write(secret, :post, explicit_path, %{}) |> json_response(201)
      assert explicit["participant_key"] == participant
      assert explicit["call_id"] == call_id

      foreign_path = "/api/tenants/#{foreign.key}/calls/#{call_id}/join-tokens"
      status = if secret == platform.secret, do: 404, else: 403
      foreign_http = rest_write(secret, :post, foreign_path, %{}) |> json_response(status)

      denied =
        tool(oauth.access_token, session, 4, "create_join_token", %{
          tenant_key: foreign.key,
          call_id: call_id
        })

      assert denied["isError"] == true
      assert denied["structuredContent"] == foreign_http

      scope = %{tenant_key: data.tenant.key, call_id: call_id, participant_key: participant}
      assert {:ok, _claim} = Calls.claim_join_token(issued["token"], scope)
      assert {:error, :token_already_claimed} = Calls.claim_join_token(issued["token"], scope)

      Repo.update_all(from(c in Vxpipe.Persistence.Schema.Call, where: c.public_id == ^call_id),
        set: [state: :ended, ended_at: DateTime.utc_now()]
      )

      ended = rest_write(secret, :post, tokens_path, %{}) |> json_response(409)

      assert tool(oauth.access_token, session, 5, "create_join_token", %{
               tenant_key: data.tenant.key,
               call_id: call_id
             })["structuredContent"] == ended
    end
  end

  test "persisted prepared hangup has HTTP/MCP parity and invalidates unredeemed tokens", data do
    {:ok, full} = Calls.issue_api_key(data.tenant.key, "Full hangup fixture", [:admin, :calls])

    {:ok, platform} =
      ApiKeyManagement.create(
        Vxpipe.Console.Test.FakeUserIdentity.principal(),
        "Platform hangup fixture",
        "platform",
        nil,
        []
      )

    {:ok, draft} = Calls.save_call_spec(data.tenant.key, spec_source())
    {:ok, _} = Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, draft.revision)

    for secret <- [data.key.secret, full.secret, platform.secret] do
      oauth = MCPOAuth.equivalent_to_api_key(secret)
      session = session(oauth.access_token)

      created =
        tool(oauth.access_token, session, 2, "create_call", %{
          tenant_key: data.tenant.key,
          call_spec_id: draft.call_spec_id
        })

      id = created["structuredContent"]["call_id"]

      token =
        tool(oauth.access_token, session, 3, "create_join_token", %{
          tenant_key: data.tenant.key,
          call_id: id
        })[
          "structuredContent"
        ]

      ended =
        tool(oauth.access_token, session, 4, "hangup_call", %{
          tenant_key: data.tenant.key,
          call_id: id
        })

      assert ended["isError"] == false
      assert ended["structuredContent"] == %{"call_id" => id, "status" => "ended"}

      response =
        rest_write(secret, :post, "/api/tenants/#{data.tenant.key}/calls/#{id}/hangup", %{})

      assert json_response(response, 200) == ended["structuredContent"]
      assert get_resp_header(response, "cache-control") == ["no-store"]
      assert {:ok, stored} = Calls.fetch_call(data.tenant.key, id)
      assert stored.state == :ended and stored.terminal_reason == :api_hangup
      assert stored.started_at == nil and stored.incarnation_id == nil

      assert {:error, _} =
               Calls.claim_join_token(token["token"], %{
                 tenant_key: data.tenant.key,
                 call_id: id,
                 participant_key: token["participant_key"]
               })
    end
  end

  test "browser call writes enforce CSRF and explicit invalid keys never fall back to a session",
       data do
    backend = Application.get_env(:vxpipe_console, :user_identity_backend)

    on_exit(fn ->
      if backend,
        do: Application.put_env(:vxpipe_console, :user_identity_backend, backend),
        else: Application.delete_env(:vxpipe_console, :user_identity_backend)
    end)

    fake = Vxpipe.Console.Test.FakeUserIdentity
    Application.put_env(:vxpipe_console, :user_identity_backend, fake)
    {:ok, draft} = Calls.save_call_spec(data.tenant.key, spec_source())
    {:ok, _} = Calls.publish_call_spec(data.tenant.key, draft.call_spec_id, draft.revision)
    path = "/api/tenants/#{data.tenant.key}/call-specs/#{draft.call_spec_id}/calls"

    auth =
      post(build_conn(), "https://localhost/auth/api/login", %{
        email: fake.email(),
        password: fake.password()
      })

    page = auth |> recycle() |> get("https://localhost/account")
    [_, csrf] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, page.resp_body)

    auth = page

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      auth
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("x-csrf-token", "invalid")
      |> post("https://localhost" <> path, %{})
    end

    invalid =
      auth
      |> recycle()
      |> put_req_header("authorization", "Bearer invalid")
      |> post("https://localhost" <> path, %{})

    assert invalid.status == 401

    created =
      auth
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("x-csrf-token", csrf)
      |> post("https://localhost" <> path, %{})

    call_id = json_response(created, 201)["call"]["id"]

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      auth
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("x-csrf-token", "invalid")
      |> post(
        "https://localhost/api/tenants/#{data.tenant.key}/calls/#{call_id}/join-tokens",
        %{}
      )
    end

    token =
      auth
      |> recycle()
      |> Map.update!(:private, &Map.delete(&1, :plug_skip_csrf_protection))
      |> put_req_header("x-csrf-token", csrf)
      |> post(
        "https://localhost/api/tenants/#{data.tenant.key}/calls/#{call_id}/join-tokens",
        %{}
      )

    assert json_response(token, 201)["call_id"] == call_id
  end

  test "disabling the delegated user invalidates existing MCP sessions", data do
    session = session(data.oauth.access_token)

    {:ok, platform} =
      ApiKeyManagement.create(
        Vxpipe.Console.Test.FakeUserIdentity.principal(),
        "Disable fixture",
        "platform",
        nil,
        []
      )

    {:ok, actor} = Vxpipe.Identity.ApiKeyActor.new(platform.key.id)

    deps = %{
      users: Vxpipe.Persistence.IdentityUserStore,
      roles: Vxpipe.Persistence.IdentityRoleStore,
      audit: Vxpipe.Persistence.IdentityAuditStore
    }

    {:ok, _} =
      Vxpipe.Identity.Accounts.update_user(
        deps,
        actor,
        data.oauth.principal.user_public_id,
        %{disabled: true}
      )

    assert request(data.oauth.access_token, "ping", 2, session).status == 401
  end

  defp session(secret) do
    initialized = request(secret, "initialize", 1, nil, initialize_params())
    [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  def search_tenants(:empty, _scope, _query, _limit, _offset), do: {:ok, {[], 0}}

  defp rest(secret, path),
    do:
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> get("https://localhost" <> path)

  defp rest_write(secret, method, path, body, headers \\ []) do
    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> secret)
      |> put_req_header("content-type", "application/json")

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

    dispatch(conn, Endpoint, method, "https://localhost" <> path, JSON.encode!(body))
  end

  defp spec_source,
    do: %{
      "schema_version" => "20261004.01",
      "defaults" => %{
        "capabilities" => %{"model_inference" => %{"provider" => "fixture", "model" => "test"}}
      },
      "incoming_call" => %{"caller" => "caller", "handled_by" => "assistant"},
      "participants" => %{
        "caller" => %{
          "type" => "human",
          "connection" => %{"service" => "web", "mode" => "receive", "admission" => "start_call"}
        },
        "assistant" => %{"type" => "agent", "prompt" => "Help."}
      }
    }

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
