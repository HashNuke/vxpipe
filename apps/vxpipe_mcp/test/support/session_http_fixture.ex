defmodule Vxpipe.MCP.SessionHTTPFixture do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  def child_spec(options) do
    Supervisor.child_spec(
      {Bandit, plug: {__MODULE__, options}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
      id: {__MODULE__, make_ref()}
    )
  end

  def endpoint(server) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}/mcp"
  end

  def init(options), do: Map.new(options)

  def call(%{method: "POST"} = conn, owner) do
    {:ok, body, conn} = read_body(conn)
    respond(conn, JSON.decode!(body), owner)
  end

  def call(%{method: "GET"} = conn, %{get_status: 405, owner: owner}) do
    send(owner, :session_http_get_rejected)
    send_resp(conn, 405, "")
  end

  def call(%{method: "GET"} = conn, %{owner: owner}) do
    conn = conn |> put_resp_content_type("text/event-stream") |> send_chunked(200)
    {:ok, conn} = chunk(conn, ": ready\n\n")
    hold(conn, :get, owner)
  end

  def call(%{method: "DELETE"} = conn, %{owner: owner}) do
    send(owner, :session_http_delete)
    send_resp(conn, 204, "")
  end

  defp respond(conn, %{"method" => "initialize", "id" => id}, fixture) do
    conn =
      if Map.get(fixture, :session, true),
        do: put_resp_header(conn, "mcp-session-id", "owned-session-fixture"),
        else: conn

    json(conn, id, %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "Session fixture", "version" => "1"}
    })
  end

  defp respond(conn, %{"method" => "notifications/initialized"}, %{owner: owner}) do
    send(owner, :session_http_initialized)
    send_resp(conn, 202, "")
  end

  defp respond(conn, %{"method" => "tools/call"}, %{owner: owner}),
    do: hold(conn, :post, owner)

  defp json(conn, id, result) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result}))
  end

  defp hold(%{adapter: {Bandit.Adapter, %{transport: %{socket: socket}}}}, method, owner) do
    send(owner, {:session_http_held, method, self()})
    result = ThousandIsland.Socket.recv(socket, 0, 10_000)
    send(owner, {:session_http_closed, method, result})
    exit(:normal)
  end
end
