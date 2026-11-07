defmodule Vxpipe.Console.Test.MCPNodeHTTP do
  @moduledoc "Controlled token-response and SSE barriers for cross-node acceptance."
  @behaviour Plug

  import Plug.Conn
  alias Vxpipe.Console.Test.OutboundMCPOAuthServer

  @impl true
  def init(options), do: options

  @impl true
  def call(%{request_path: "/token"} = conn, options) do
    conn
    |> register_before_send(fn response ->
      hold? = Agent.get(options.state, & &1.hold_tokens)
      send(options.owner, {:node_token_response, self(), response.status})

      if hold? do
        receive do
          :release_token -> response
        after
          10_000 -> raise "fixture token response was not released"
        end
      else
        response
      end
    end)
    |> OutboundMCPOAuthServer.call(options.state)
  end

  def call(%{request_path: "/mcp"} = conn, options) do
    authorization = get_req_header(conn, "authorization")
    workspace = get_req_header(conn, "x-workspace")

    valid? =
      Agent.get(options.state, fn state ->
        Enum.any?(state.access, &(authorization == ["Bearer " <> &1])) and
          workspace == ["node-workspace"]
      end)

    send(options.owner, {:node_mcp_request, conn.method, authorization, workspace})
    if valid?, do: mcp(conn, options), else: send_resp(conn, 401, "")
  end

  defp mcp(%{method: "GET"} = conn, options) do
    cursor = get_req_header(conn, "last-event-id")
    conn = conn |> put_resp_content_type("text/event-stream") |> send_chunked(200)
    {:ok, conn} = chunk(conn, "id: node-event\nretry: 10\ndata: \n\n")
    send(options.owner, {:node_sse_stream, self(), cursor})

    receive do
      :close_stream -> conn
    after
      10_000 -> conn
    end
  end

  defp mcp(%{method: "DELETE"} = conn, _options), do: send_resp(conn, 204, "")

  defp mcp(%{method: "POST"} = conn, options) do
    {:ok, body, conn} = read_body(conn)
    request = JSON.decode!(body)
    send(options.owner, {:node_rpc, request["method"]})

    case request do
      %{"method" => "initialize", "id" => id} ->
        conn
        |> put_resp_header("mcp-session-id", "node-session")
        |> reply(id, %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{"tools" => %{}},
          "serverInfo" => %{"name" => "Node tools", "version" => "1"}
        })

      %{"method" => "notifications/initialized"} ->
        send_resp(conn, 202, "")

      %{"method" => "tools/list", "id" => id} ->
        reply(conn, id, %{
          "tools" => [%{"name" => "node_tool", "inputSchema" => %{"type" => "object"}}]
        })

      %{"method" => "tools/call", "id" => id} ->
        reply(conn, id, %{"content" => [%{"type" => "text", "text" => "node-result"}]})
    end
  end

  defp reply(conn, id, result),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, JSON.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result}))
end
