defmodule Vxpipe.Gateway.MCP.CallToolsTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{Administration, TestMemoryRepository}
  alias Vxpipe.Gateway.CallAdmission
  alias Vxpipe.Gateway.HTTP.Endpoint
  alias Vxpipe.Gateway.MCP.{Admission, Authentication}

  @version "2025-11-25"

  setup do
    repository = start_supervised!(TestMemoryRepository)

    options = [
      credential_repository: {TestMemoryRepository, repository},
      call_spec_repository: {TestMemoryRepository, repository},
      call_repository: {TestMemoryRepository, repository},
      registries: %{host_tools: %{}}
    ]

    {:ok, tenant, key} = Administration.bootstrap_tenant("MCP calls", [:calls], options)
    {:ok, revision} = Calls.save_call_spec(tenant.key, source(), options)
    {:ok, _} = Calls.publish_call_spec(tenant.key, revision.call_spec_id, 1, options)
    admission = start_supervised!({Admission, name: nil})

    endpoint =
      Endpoint.init(
        mcp: [
          enabled: true,
          allowed_hosts: ["localhost"],
          admission: admission,
          authentication: {Authentication, options}
        ],
        call_admission: [enabled: true, backend: {CallAdmission, options}]
      )

    %{
      endpoint: endpoint,
      secret: key.secret,
      tenant: tenant.key,
      spec: revision.call_spec_id,
      options: options
    }
  end

  test "MCP and HTTP share prepared creation, variables and tenant-wide replay", c do
    session = initialize(c)

    arguments = %{
      tenant_key: c.tenant,
      call_spec_id: c.spec,
      variables: %{data: %{private: "pinned-sentinel"}},
      idempotency_key: "web-call"
    }

    created = invoke(c, session, 2, "create_call", arguments) |> result()
    assert created["isError"] == false
    assert %{"call_id" => id} = created["structuredContent"]
    assert map_size(created["structuredContent"]) == 1
    assert [%{"text" => text, "type" => "text"}] = created["content"]
    assert JSON.decode!(text) == %{"call_id" => id}
    {:ok, call} = Calls.fetch_call(c.tenant, id, c.options)
    assert call.state == :prepared
    assert call.incarnation_id == nil
    assert call.initial_variables == %{"data" => %{"private" => "pinned-sentinel"}}
    refute JSON.encode!(created) =~ "pinned-sentinel"

    response =
      conn(
        :post,
        "/api/tenants/#{c.tenant}/call-specs/#{c.spec}/calls",
        JSON.encode!(%{variables: arguments.variables})
      )
      |> put_req_header("authorization", "Bearer " <> c.secret)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "web-call")
      |> Endpoint.call(c.endpoint)

    assert response.status == 200
    assert JSON.decode!(response.resp_body)["call"]["id"] == id
    assert invoke(c, session, 3, "create_call", arguments) |> result() == created

    conflict = invoke(c, session, 4, "create_call", %{arguments | variables: %{}}) |> result()
    assert conflict["isError"] == true
    assert conflict["structuredContent"]["error"]["code"] == "idempotency_conflict"
  end

  test "hangup tool and HTTP replay agree and reject client runtime selectors", c do
    session = initialize(c)

    created =
      invoke(c, session, 2, "create_call", %{tenant_key: c.tenant, call_spec_id: c.spec})
      |> result()

    id = created["structuredContent"]["call_id"]
    ended = invoke(c, session, 3, "hangup_call", %{tenant_key: c.tenant, call_id: id}) |> result()
    assert ended["isError"] == false
    assert ended["structuredContent"] == %{"call_id" => id, "status" => "ended"}

    response =
      conn(:post, "/api/tenants/#{c.tenant}/calls/#{id}/hangup", "{}")
      |> put_req_header("authorization", "Bearer " <> c.secret)
      |> put_req_header("content-type", "application/json")
      |> Endpoint.call(c.endpoint)

    assert response.status == 200
    assert JSON.decode!(response.resp_body) == ended["structuredContent"]

    assert invoke(c, session, 4, "hangup_call", %{
             tenant_key: c.tenant,
             call_id: id,
             incarnation_id: "override"
           }).status == 400

    catalog = request(c, session, 5, "tools/list", %{}) |> result()
    tool = Enum.find(catalog["tools"], &(&1["name"] == "hangup_call"))

    assert tool["annotations"] == %{
             "destructiveHint" => true,
             "idempotentHint" => true,
             "openWorldHint" => true,
             "readOnlyHint" => false
           }
  end

  test "MCP issues a pinned single-use token and denies invalid or foreign requests", c do
    session = initialize(c)

    created =
      invoke(c, session, 2, "create_call", %{tenant_key: c.tenant, call_spec_id: c.spec})
      |> result()

    id = created["structuredContent"]["call_id"]

    issued =
      invoke(c, session, 3, "create_join_token", %{
        tenant_key: c.tenant,
        call_id: id,
        join_token_ttl_seconds: 300
      })
      |> result()

    assert issued["isError"] == false

    assert %{
             "call_id" => ^id,
             "participant_key" => participant,
             "token" => secret,
             "expires_at" => expires
           } = issued["structuredContent"]

    assert {:ok, _, 0} = DateTime.from_iso8601(expires)
    scope = %{tenant_key: c.tenant, call_id: id, participant_key: participant}
    assert {:ok, _claim} = Calls.claim_join_token(secret, scope, c.options)
    assert {:error, :token_already_claimed} = Calls.claim_join_token(secret, scope, c.options)

    for {name, args} <- [
          {"create_call", %{tenant_key: c.tenant, call_spec_id: c.spec, variables: []}},
          {"create_call", %{tenant_key: c.tenant, call_spec_id: c.spec, tenant_id: 1}},
          {"create_join_token",
           %{tenant_key: c.tenant, call_id: id, join_token_ttl_seconds: "300"}},
          {"create_join_token", %{tenant_key: c.tenant, call_id: id, join_token_ttl_seconds: 299}}
        ] do
      response = invoke(c, session, System.unique_integer([:positive]), name, args)
      assert response.status == 400
      assert JSON.decode!(response.resp_body)["error"]["code"] == -32602
    end

    foreign =
      invoke(c, session, 20, "create_join_token", %{tenant_key: "BBBBBBBBBBBBBBBB", call_id: id})
      |> result()

    assert foreign["isError"] == true
    assert foreign["structuredContent"]["error"]["code"] == "not_authorized"
  end

  test "calls scope exposes call tools and admin-only scope cannot invoke them", c do
    session = initialize(c)
    catalog = request(c, session, 2, "tools/list", %{}) |> result()
    names = Enum.map(catalog["tools"], & &1["name"])
    assert "create_call" in names and "create_join_token" in names
    refute "create_call_spec" in names

    {:ok, admin} = Administration.issue_api_key(c.tenant, "admin", [:admin], c.options)
    c = %{c | secret: admin.secret}
    session = initialize(c)

    names =
      request(c, session, 2, "tools/list", %{})
      |> result()
      |> Map.fetch!("tools")
      |> Enum.map(& &1["name"])

    refute "create_call" in names or "create_join_token" in names

    assert invoke(c, session, 3, "create_call", %{tenant_key: c.tenant, call_spec_id: c.spec}).status ==
             403
  end

  defp source do
    %{
      schema_version: "20261004.01",
      incoming_call: %{caller: "caller", handled_by: "assistant"},
      defaults: %{capabilities: %{model_inference: %{provider: "fixture", model: "test"}}},
      call_variables: %{
        sections: %{
          "data" => %{
            schema: %{
              type: "object",
              properties: %{"private" => %{type: "string"}},
              additionalProperties: false
            }
          }
        }
      },
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"}
        },
        "assistant" => %{type: "agent", prompt: "Help."}
      }
    }
  end

  defp result(response), do: JSON.decode!(response.resp_body)["result"]

  defp invoke(c, session, id, name, args),
    do: request(c, session, id, "tools/call", %{name: name, arguments: args})

  defp initialize(c) do
    response =
      request(c, nil, 1, "initialize", %{
        protocolVersion: @version,
        capabilities: %{},
        clientInfo: %{name: "fixture", version: "1"}
      })

    assert response.status == 200
    [session] = get_resp_header(response, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  defp request(c, session, id, method, params) do
    connection =
      conn(
        :post,
        "https://localhost/mcp",
        JSON.encode!(%{jsonrpc: "2.0", id: id, method: method, params: params})
      )
      |> put_req_header("authorization", "Bearer " <> c.secret)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", @version)

    connection =
      if session, do: put_req_header(connection, "mcp-session-id", session), else: connection

    Endpoint.call(connection, c.endpoint)
  end
end
