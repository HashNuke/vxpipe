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

  def request_count(method) when is_binary(method) do
    method
    |> collect_requests(0)
    |> tap(fn _count -> drain_other_requests() end)
  end

  def take_request(method) when is_binary(method) do
    receive do
      {:fault_server_request, ^method, request} -> request
      {:fault_server_request, _other_method, _request} -> take_request(method)
    after
      100 -> nil
    end
  end

  def init(opts), do: opts

  def call(%{method: "GET"} = conn, {_fault, owner}) do
    send(owner, {:fault_server_request, :stream, nil})

    conn
    |> put_resp_content_type("text/event-stream")
    |> send_resp(200, ": stream ready\n\n")
  end

  def call(%{method: "POST"} = conn, {fault, owner}) do
    {:ok, body, conn} = read_body(conn)
    request = Jason.decode!(body)
    method = Map.get(request, "method")
    send(owner, {:fault_server_request, method, request})
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

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :compressed) do
    payload = success_payload(id, "compressed")

    conn
    |> put_resp_header("content-encoding", "gzip")
    |> json_response(200, payload)
  end

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :chunked_oversized) do
    id
    |> success_payload(String.duplicate("x", 1_500))
    |> Jason.encode!()
    |> then(&send_chunked_payload(conn, "application/json", &1))
  end

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :sse_oversized) do
    event =
      "event: message\ndata: #{Jason.encode!(success_payload(id, String.duplicate("x", 1_500)))}\n\n"

    send_chunked_payload(conn, "text/event-stream", event)
  end

  defp respond(conn, %{"method" => "tools/call", "id" => id}, :slow) do
    receive do
      :release_fault_response -> json_response(conn, 200, success_payload(id, "late"))
    after
      500 -> json_response(conn, 200, success_payload(id, "late"))
    end
  end

  defp respond(_conn, %{"method" => "tools/call"}, :disconnect), do: exit(:shutdown)

  defp json_response(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end

  defp send_chunked_payload(conn, content_type, payload) do
    {first, second} = String.split_at(payload, 700)

    conn =
      conn
      |> put_resp_content_type(content_type)
      |> send_chunked(200)
      |> send_chunk(first)

    send_chunk(conn, second)
  end

  defp send_chunk(conn, data) do
    case chunk(conn, data) do
      {:ok, next_conn} -> next_conn
      {:error, _reason} -> conn
    end
  end

  defp success_payload(id, text) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"content" => [%{"type" => "text", "text" => text}]}
    }
  end

  defp collect_requests(method, count) do
    receive do
      {:fault_server_request, ^method, _request} -> collect_requests(method, count + 1)
      {:fault_server_request, _other, _request} -> collect_requests(method, count)
    after
      0 -> count
    end
  end

  defp drain_other_requests do
    receive do
      {:fault_server_request, _method, _request} -> drain_other_requests()
    after
      0 -> :ok
    end
  end
end
