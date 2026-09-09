defmodule Vxpipe.MCP.FaultServer do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @session_id "vxpipe-fault-session"

  def child_spec(opts) do
    fault = Keyword.fetch!(opts, :fault)
    owner = Keyword.fetch!(opts, :owner)

    Supervisor.child_spec(
      {Bandit,
       plug: {__MODULE__, {fault, owner}}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
      id: {__MODULE__, make_ref()}
    )
  end

  def endpoint(server) when is_pid(server) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}/mcp"
  end

  def init(opts), do: opts

  def call(%{method: "GET"} = conn, {_fault, owner}) do
    send(owner, {:fault_server_request, :stream})

    conn
    |> put_resp_content_type("text/event-stream")
    |> send_resp(200, ": stream ready\n\n")
  end

  def call(%{method: "POST"} = conn, {fault, owner}) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)
    method = Map.get(request, "method")
    send(owner, {:fault_server_request, method})
    respond(conn, request, fault)
  end

  defp respond(conn, %{"method" => "initialize", "id" => id}, _fault) do
    result = %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "vxpipe-fault-fixture", "version" => "1"}
    }

    conn
    |> put_resp_header("mcp-session-id", @session_id)
    |> json_response(200, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp respond(conn, %{"method" => "notifications/initialized"}, _fault) do
    send_resp(conn, 202, "")
  end

  defp respond(conn, %{"method" => "tools/list", "id" => id}, _fault) do
    tool = %{
      "name" => "fault_tool",
      "inputSchema" => %{"type" => "object", "additionalProperties" => false}
    }

    json_response(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"tools" => [tool]}
    })
  end

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :remote_error) do
    json_response(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32_000,
        "message" => "authorization: Bearer fixture-private-value"
      }
    })
  end

  defp respond(conn, %{"method" => "tools/call"}, :wrong_id) do
    json_response(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => "unrelated-request",
      "result" => %{"content" => []}
    })
  end

  defp respond(conn, %{"method" => "tools/call"}, :malformed) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, "{not-json")
  end

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :unsupported) do
    json_response(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => -32_601, "message" => "Method not found"}
    })
  end

  defp json_response(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
