defmodule Vxpipe.MCP.CumulativeSSEServer do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  @session_id "vxpipe-cumulative-sse-session"

  def child_spec(opts) do
    owner = Keyword.fetch!(opts, :owner)

    Supervisor.child_spec(
      {Bandit, plug: {__MODULE__, owner}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
      id: {__MODULE__, make_ref()}
    )
  end

  def endpoint(server) when is_pid(server) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}/mcp"
  end

  def init(owner), do: owner

  def call(%{method: "GET"} = conn, owner) do
    case get_req_header(conn, "last-event-id") do
      [] -> initial_stream(conn, owner)
      last_event_id -> resumed_stream(conn, owner, last_event_id)
    end
  end

  def call(%{method: "POST"} = conn, owner) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)
    send(owner, {:cumulative_sse_request, Map.get(request, "method"), request})
    respond(conn, request, owner)
  end

  defp initial_stream(conn, owner) do
    conn = open_stream(conn, "id: event-1\nretry: 10\ndata: \n\n")
    send(owner, {:cumulative_sse_initial_stream, self()})
    await_close(conn)
  end

  defp resumed_stream(conn, owner, last_event_id) do
    conn = open_stream(conn)
    send(owner, {:cumulative_sse_resumed_stream, self(), last_event_id})

    receive do
      {:emit_progress, progress_token} ->
        conn
        |> send_chunk(
          "id: event-3\ndata: #{Jason.encode!(progress_event(progress_token, 1))}\n\n"
        )
        |> send_chunk(
          "id: event-4\ndata: #{Jason.encode!(progress_event(progress_token, 2))}\n\n"
        )
        |> await_close()
    after
      5_000 -> conn
    end
  end

  defp respond(conn, %{"method" => "initialize", "id" => id}, _owner) do
    result = %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "vxpipe-cumulative-sse-fixture", "version" => "1"}
    }

    conn
    |> put_resp_header("mcp-session-id", @session_id)
    |> json_response(200, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp respond(conn, %{"method" => "notifications/initialized"}, _owner) do
    send_resp(conn, 202, "")
  end

  defp respond(conn, %{"method" => "tools/list", "id" => id}, _owner) do
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

  defp respond(conn, %{"method" => "tools/call"}, owner) do
    conn = open_stream(conn, "id: event-2\nretry: 10\ndata: \n\n")
    send(owner, {:cumulative_sse_post_stream, self()})
    await_close(conn)
  end

  defp open_stream(conn, initial_data \\ nil) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    if initial_data, do: send_chunk(conn, initial_data), else: conn
  end

  defp await_close(conn) do
    receive do
      :close_stream -> conn
    after
      5_000 -> conn
    end
  end

  defp send_chunk(conn, data) do
    case chunk(conn, data) do
      {:ok, next_conn} -> next_conn
      {:error, _reason} -> conn
    end
  end

  defp json_response(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp progress_event(progress_token, progress) do
    %{
      "jsonrpc" => "2.0",
      "method" => "notifications/progress",
      "params" => %{
        "progressToken" => progress_token,
        "progress" => progress,
        "message" => String.duplicate("x", 600)
      }
    }
  end
end
