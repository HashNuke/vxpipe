defmodule Vxpipe.Gateway.MCP.ServerBoundaryTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ExMCP.HttpPlug
  alias Vxpipe.Gateway.Test.MCPProbeHandler

  @version "2025-11-25"

  test "configured handler negotiates the selected profile and exposes only implemented tools" do
    options = options()
    {session_id, initialized} = initialize(options, "key-one")

    assert %{
             "id" => 1,
             "result" => %{
               "protocolVersion" => @version,
               "capabilities" => %{"tools" => %{}},
               "serverInfo" => %{"name" => "vxpipe-probe", "version" => "1"}
             }
           } = Jason.decode!(initialized.resp_body)

    notification = request("notifications/initialized", nil, session_id, "key-one", options)
    assert notification.status == 202
    assert notification.resp_body == ""

    ping = request("ping", 2, session_id, "key-one", options)
    assert Jason.decode!(ping.resp_body) == %{"jsonrpc" => "2.0", "id" => 2, "result" => %{}}

    tools = request("tools/list", 3, session_id, "key-one", options)
    assert %{"result" => %{"tools" => []}} = Jason.decode!(tools.resp_body)
    assert_received {:probe_actor, "key-one"}

    unavailable =
      request("tools/call", 4, session_id, "key-one", options, %{
        "name" => "not_implemented",
        "arguments" => %{}
      })

    assert %{"error" => %{"code" => -32602}} = Jason.decode!(unavailable.resp_body)
  end

  test "trusted per-request key identity binds the session and authenticated DELETE ends it" do
    options = options()
    {session_id, _initialized} = initialize(options, "key-one")

    denied = request("tools/list", 2, session_id, "other-key", options)
    assert denied.status == 404
    refute_received {:probe_actor, "other-key"}

    deleted =
      conn(:delete, "/mcp")
      |> assign(:authenticated_key_id, "key-one")
      |> put_req_header("mcp-session-id", session_id)
      |> put_req_header("mcp-protocol-version", @version)
      |> HttpPlug.call(options)

    assert deleted.status == 204
    assert request("ping", 3, session_id, "key-one", options).status == 404
  end

  @tag capture_log: true
  test "configured handler deadline returns a bounded error and terminates request work" do
    options = options(block: true, handler_call_timeout: 20)
    {session_id, _initialized} = initialize(options, "key-one")
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        request("tools/list", 2, session_id, "key-one", options)
      end)

    assert_receive {:probe_blocked, handler}
    monitor = Process.monitor(handler)
    response = Task.await(task, 5_000)

    assert %{"error" => %{"code" => -32603, "data" => %{"type" => "handler_timeout"}}} =
             Jason.decode!(response.resp_body)

    assert_receive {:DOWN, ^monitor, :process, ^handler, _reason}
  end

  defp initialize(options, actor) do
    response =
      request("initialize", 1, nil, actor, options, %{
        "protocolVersion" => @version,
        "capabilities" => %{},
        "clientInfo" => %{"name" => "vxpipe-probe-client", "version" => "1"}
      })

    assert response.status == 200
    assert [session_id] = get_resp_header(response, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session_id) end)
    {session_id, response}
  end

  defp options(overrides \\ []) do
    owner = self()

    HttpPlug.init(
      handler: MCPProbeHandler,
      handler_opts: fn conn ->
        %{
          actor: conn.assigns.authenticated_key_id,
          owner: owner,
          block: Keyword.get(overrides, :block, false)
        }
      end,
      principal_id: fn conn -> conn.assigns.authenticated_key_id end,
      protocol_mode: :legacy_only,
      legacy_http_sse: false,
      oauth_enabled: false,
      cors_enabled: false,
      allowed_hosts: ["www.example.com"],
      allowed_origins: [],
      body_limit: 131_072,
      handler_call_timeout: Keyword.get(overrides, :handler_call_timeout, 1_000)
    )
  end

  defp request(method, id, session_id, actor, options, params \\ %{}) do
    message = %{"jsonrpc" => "2.0", "method" => method, "params" => params}
    message = if is_nil(id), do: message, else: Map.put(message, "id", id)

    conn =
      conn(:post, "/mcp", Jason.encode!(message))
      |> assign(:authenticated_key_id, actor)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")
      |> put_req_header("mcp-protocol-version", @version)

    conn = if session_id, do: put_req_header(conn, "mcp-session-id", session_id), else: conn
    HttpPlug.call(conn, options)
  end
end
