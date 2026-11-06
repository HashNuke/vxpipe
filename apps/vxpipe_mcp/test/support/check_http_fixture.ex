defmodule Vxpipe.MCP.CheckHTTPFixture do
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

  def init(options), do: options

  def call(%{method: "POST"} = conn, options) do
    {:ok, body, conn} = read_body(conn)
    request = JSON.decode!(body)
    method = Map.get(request, "method")
    send(Keyword.fetch!(options, :owner), {:check_http, method, conn.req_headers})

    if Keyword.get(options, :hold) == method do
      hold(conn, method, options)
    else
      respond(conn, request, options)
    end
  end

  def call(%{method: "DELETE"} = conn, options) do
    send(Keyword.fetch!(options, :owner), {:check_http, "DELETE", conn.req_headers})

    if Keyword.get(options, :hold) == "DELETE",
      do: hold(conn, "DELETE", options),
      else: send_resp(conn, 204, "")
  end

  def call(conn, options) do
    send(Keyword.fetch!(options, :owner), {:check_http_unexpected, conn.method})
    send_resp(conn, 405, "")
  end

  defp respond(conn, %{"method" => "initialize", "id" => id}, options) do
    conn =
      if Keyword.get(options, :session, true),
        do: put_resp_header(conn, "mcp-session-id", "check-fixture-session"),
        else: conn

    conn
    |> json(id, %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "Check fixture", "version" => "1"}
    })
  end

  defp respond(conn, %{"method" => "notifications/initialized"}, _options),
    do: send_resp(conn, 202, "")

  defp respond(conn, %{"method" => "tools/list", "id" => id}, _options),
    do: json(conn, id, %{"tools" => []})

  defp json(conn, id, result),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result}))

  defp hold(%{adapter: {Bandit.Adapter, %{transport: %{socket: socket}}}}, method, options) do
    send(Keyword.fetch!(options, :owner), {:check_http_held, method})
    result = ThousandIsland.Socket.recv(socket, 0, 2_000)
    send(Keyword.fetch!(options, :owner), {:check_http_closed, method, result})
    exit(:normal)
  end
end
