defmodule Vxpipe.Gateway.MCP.TenantToolsTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Calls.Tenant
  alias Vxpipe.Gateway.Test.MCPOAuth
  alias Vxpipe.Gateway.MCP.{Admission, Endpoint}

  @key "AAAAAAAAAAAAAAAA"
  @foreign "BBBBBBBBBBBBBBBB"
  @version "2025-11-25"

  setup do
    actor = MCPOAuth.actor(@key)
    admission = start_supervised!({Admission, name: nil})

    options = [
      enabled: true,
      issuer: "https://localhost",
      resource: "https://localhost/mcp",
      allowed_hosts: ["localhost"],
      admission: admission,
      authentication: {__MODULE__, actor},
      call_options: [admin_repository: {__MODULE__, self()}]
    ]

    %{actor: actor, options: options}
  end

  test "tenant discovery advertises bounded schemas and returns safe scoped projections",
       context do
    session = initialize(context.options)
    catalog = request(context.options, session, "tools/list", 2)
    tools = JSON.decode!(catalog.resp_body)["result"]["tools"]
    tools = Enum.filter(tools, &(&1["name"] in ["list_tenants", "get_tenant"]))
    assert Enum.map(tools, & &1["name"]) == ["list_tenants", "get_tenant"]
    assert Enum.all?(tools, &(&1["annotations"]["readOnlyHint"] == true))
    assert Enum.all?(tools, &(&1["inputSchema"]["additionalProperties"] == false))

    listed = invoke(context.options, session, 3, "list_tenants", %{})
    result = JSON.decode!(listed.resp_body)["result"]

    assert result["structuredContent"] == %{
             "items" => [
               %{
                 "tenant_key" => @key,
                 "name" => "Fixture",
                 "created_at" => "2026-10-15T00:00:00Z"
               }
             ],
             "pagination" => %{"page" => 1, "page_size" => 25, "total" => 1, "total_pages" => 1}
           }

    assert [%{"type" => "text", "text" => text}] = result["content"]
    assert JSON.decode!(text) == result["structuredContent"]
    assert_received {:search, {:keys, [@key]}, 25, 0}

    detail = invoke(context.options, session, 4, "get_tenant", %{"tenant_key" => @key})

    assert JSON.decode!(detail.resp_body)["result"]["structuredContent"] == %{
             "tenant_key" => @key,
             "name" => "Fixture",
             "created_at" => "2026-10-15T00:00:00Z"
           }

    foreign = invoke(context.options, session, 5, "get_tenant", %{"tenant_key" => @foreign})
    assert JSON.decode!(foreign.resp_body)["result"]["isError"] == true

    assert JSON.decode!(foreign.resp_body)["result"]["structuredContent"] ==
             %{"error" => %{"code" => "tenant_not_found"}}

    refute_received {:candidates, @foreign}
  end

  test "arguments reject coercion, nulls, unexpected authority and excessive page size",
       context do
    session = initialize(context.options)

    for {arguments, id} <-
          Enum.with_index(
            [
              %{"page" => "1"},
              %{"page" => nil},
              %{"page_size" => 51},
              %{"api_key" => "private-argument-sentinel"},
              %{"tenant_id" => "forged"}
            ],
            2
          ) do
      response = invoke(context.options, session, id, "list_tenants", arguments)
      assert %{"error" => %{"code" => -32602}} = JSON.decode!(response.resp_body)
      refute response.resp_body =~ "private-argument-sentinel"
    end

    refute_received {:search, _, _, _}
  end

  test "tool visibility and invocation both enforce the shared application policy", context do
    options =
      Keyword.put(
        context.options,
        :authentication,
        {__MODULE__, %{context.actor | grants: MapSet.new()}}
      )

    session = initialize(options)
    listed = request(options, session, "tools/list", 2)
    assert JSON.decode!(listed.resp_body)["result"]["tools"] == []
    denied = invoke(options, session, 3, "list_tenants", %{})
    assert denied.status == 403
    refute_received {:search, _, _, _}
  end

  test "MCP request metadata remains separate from the public tool arguments", context do
    session = initialize(context.options)

    response =
      request(context.options, session, "tools/call", 2, %{
        "name" => "list_tenants",
        "arguments" => %{},
        "_meta" => %{"progressToken" => "fixture-progress"}
      })

    assert JSON.decode!(response.resp_body)["result"]["isError"] == false
    assert_received {:search, {:keys, [@key]}, 25, 0}
  end

  test "callback exceptions, exits and throws return safe internal errors", context do
    for {failure, id} <- Enum.with_index([:raise, :exit, :throw], 2) do
      options =
        Keyword.put(context.options, :call_options, admin_repository: {__MODULE__, failure})

      session = initialize(options)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          response = invoke(options, session, id, "list_tenants", %{})
          assert %{"error" => %{"code" => -32603}} = JSON.decode!(response.resp_body)
          refute response.resp_body =~ "private-callback-sentinel"
        end)

      refute log =~ "private-callback-sentinel"
    end
  end

  test "unrecognized tool names never enter dependency telemetry", context do
    session = initialize(context.options)
    handler_id = {__MODULE__, make_ref()}
    event = [:ex_mcp, :server, :tool, :called]
    :ok = :telemetry.attach(handler_id, event, &__MODULE__.on_tool/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
    response = invoke(context.options, session, 2, "private-tool-name-sentinel", %{})
    assert %{"error" => %{"code" => -32602}} = JSON.decode!(response.resp_body)
    refute_received {:tool_called, "private-tool-name-sentinel"}

    missing = request(context.options, session, "tools/call", 3, :absent)
    assert %{"error" => %{"code" => -32602}} = JSON.decode!(missing.resp_body)
    refute_received {:tool_called, nil}
  end

  def on_tool(_event, _measurements, metadata, owner),
    do: send(owner, {:tool_called, metadata.tool_name})

  def authenticate(actor, _secret), do: {:ok, actor}

  def search_tenants(:raise, _, _, _, _), do: raise("private-callback-sentinel")
  def search_tenants(:exit, _, _, _, _), do: exit({:private, "private-callback-sentinel"})
  def search_tenants(:throw, _, _, _, _), do: throw("private-callback-sentinel")

  def search_tenants(owner, scope, _query, limit, offset) do
    send(owner, {:search, scope, limit, offset})
    {:ok, {[tenant()], 1}}
  end

  def tenant_candidates(owner, {:keys, [key]}, _limit) do
    send(owner, {:candidates, key})
    {:ok, [tenant()]}
  end

  defp tenant, do: %Tenant{key: @key, name: "Fixture", inserted_at: ~U[2026-10-15 00:00:00Z]}

  defp initialize(options) do
    response =
      request(options, nil, "initialize", 1, %{
        "protocolVersion" => @version,
        "capabilities" => %{},
        "clientInfo" => %{"name" => "fixture", "version" => "1"}
      })

    assert response.status == 200
    [session] = get_resp_header(response, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)
    session
  end

  defp invoke(options, session, id, name, arguments),
    do: request(options, session, "tools/call", id, %{"name" => name, "arguments" => arguments})

  defp request(options, session, method, id, params \\ %{}) do
    body = %{jsonrpc: "2.0", id: id, method: method}
    body = if params == :absent, do: body, else: Map.put(body, :params, params)

    conn =
      conn(
        :post,
        "https://localhost/mcp",
        JSON.encode!(body)
      )
      |> put_req_header("authorization", "Bearer synthetic")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", @version)

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn
    Endpoint.call(conn, Endpoint.init(options))
  end
end
