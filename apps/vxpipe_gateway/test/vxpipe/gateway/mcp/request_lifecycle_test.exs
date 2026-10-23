defmodule Vxpipe.Gateway.MCP.RequestLifecycleTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias Vxpipe.Gateway.Test.MCPOAuth
  alias Vxpipe.Gateway.MCP.{Admission, Endpoint, Protocol}
  alias Vxpipe.Gateway.Test.MCPProbeHandler

  setup do
    admission = start_supervised!({Admission, name: nil, max_concurrency: 1})
    tasks = start_supervised!({Task.Supervisor, name: nil})

    options =
      Endpoint.init(
        enabled: true,
        issuer: "https://localhost",
        resource: "https://localhost/mcp",
        allowed_hosts: ["localhost"],
        admission: admission,
        authentication: {__MODULE__, :allow}
      )

    %{admission: admission, tasks: tasks, options: options}
  end

  test "request-owner death releases admission even before authentication finishes", context do
    options = %{context.options | authentication: {__MODULE__, {:block, self()}}}

    {:ok, request} =
      Task.Supervisor.start_child(context.tasks, fn -> request(options, "ping", 1) end)

    assert_receive {:authentication_started, ^request}, 1_000
    assert request(context.options, "ping", 2).status == 503

    monitor = Process.monitor(request)
    Process.exit(request, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^request, :killed}, 1_000
    _ = :sys.get_state(context.admission)

    # GET exercises the same admission/authentication boundary without allocating
    # a session. Reaching the method response proves the dead owner released it.
    assert get(context.options).status == 405
  end

  test "request-owner death stops its ExMCP callback and releases Gateway admission", context do
    owner = self()

    # Only the callback is instrumented. Keep the protocol/security options chosen
    # by Vxpipe's endpoint and exercise the real ExMCP request-worker boundary.
    protocol =
      Map.merge(context.options.protocol, %{
        handler: MCPProbeHandler,
        handler_opts: fn conn ->
          %{actor: conn.assigns.mcp_identity, owner: owner, block: true}
        end
      })

    options = %{context.options | protocol: protocol}
    initialized = request(options, "initialize", 1, nil, initialize_params())
    assert initialized.status == 200
    assert [session] = get_resp_header(initialized, "mcp-session-id")
    on_exit(fn -> ExMCP.SessionManager.terminate_session(session) end)

    {:ok, request} =
      Task.Supervisor.start_child(context.tasks, fn ->
        request(options, "tools/list", 2, session)
      end)

    assert_receive {:probe_blocked, handler}, 1_000
    assert get(options).status == 503
    request_monitor = Process.monitor(request)
    handler_monitor = Process.monitor(handler)
    Process.exit(request, :kill)
    assert_receive {:DOWN, ^request_monitor, :process, ^request, :killed}, 1_000
    assert_receive {:DOWN, ^handler_monitor, :process, ^handler, :killed}, 1_000
    _ = :sys.get_state(context.admission)

    assert get(options).status == 405
    # Losing a request does not revoke its authenticated MCP session. The next
    # request can continue with a fresh JSON-RPC ID and the same OAuth grant.
    assert request(options, "ping", 3, session).status == 200
  end

  def authenticate({:block, owner}, secret) do
    send(owner, {:authentication_started, self()})
    receive do: (:release -> authenticate(:allow, secret))
  end

  def authenticate(:allow, "synthetic-key"), do: {:ok, MCPOAuth.actor()}

  defp request(options, method, id, session \\ nil, params \\ %{}) do
    conn =
      conn(
        :post,
        "https://localhost/mcp",
        JSON.encode!(%{jsonrpc: "2.0", method: method, id: id, params: params})
      )
      |> put_req_header("authorization", "Bearer synthetic-key")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", Protocol.version())

    conn = if session, do: put_req_header(conn, "mcp-session-id", session), else: conn
    Endpoint.call(conn, options)
  end

  defp get(options) do
    conn(:get, "https://localhost/mcp")
    |> put_req_header("authorization", "Bearer synthetic-key")
    |> Endpoint.call(options)
  end

  defp initialize_params do
    %{
      protocolVersion: Protocol.version(),
      capabilities: %{},
      clientInfo: %{name: "local-lifecycle-test", version: "1"}
    }
  end
end
