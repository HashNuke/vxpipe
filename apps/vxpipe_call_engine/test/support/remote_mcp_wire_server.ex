defmodule Vxpipe.CallEngine.RemoteMCPWireServer do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  def child_spec(options) do
    owner = Keyword.fetch!(options, :owner)

    state = %{
      authorization: Keyword.get(options, :authorization),
      headers: Keyword.get(options, :headers, []),
      hold_stream: Keyword.get(options, :hold_stream, false),
      hold_invocation: Keyword.get(options, :hold_invocation, false),
      hold_initialization: Keyword.get(options, :hold_initialization, false),
      owner: owner,
      redirect_to: Keyword.get(options, :redirect_to),
      request_label: Keyword.get(options, :request_label),
      session_id: "wire-session-#{System.unique_integer([:positive, :monotonic])}"
    }

    Supervisor.child_spec(
      {Bandit, plug: {__MODULE__, state}, ip: {127, 0, 0, 1}, port: 0, startup_log: false},
      id: {__MODULE__, make_ref()}
    )
  end

  def endpoint(server) when is_pid(server) do
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}/mcp"
  end

  @impl true
  def init(state), do: state

  @impl true
  def call(%{request_path: path} = conn, _state) when path != "/mcp",
    do: send_resp(conn, 404, "not found")

  def call(%{method: "GET"} = conn, state) do
    send(state.owner, {:remote_mcp_wire_stream, authorization(conn)})

    if state.hold_stream do
      hold_stream(conn, state.owner)
    else
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_resp(200, ": stream ready\n\n")
    end
  end

  def call(%{method: "POST"} = conn, state) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, request} <- Jason.decode(body) do
      label = state.request_label || Map.get(request, "method")
      send(state.owner, {:remote_mcp_wire_request, label, authorization(conn), request})

      send(
        state.owner,
        {:remote_mcp_wire_session_request, label, get_req_header(conn, "mcp-session-id")}
      )

      respond(conn, request, state)
    else
      _invalid -> send_resp(conn, 400, "invalid request")
    end
  end

  def call(%{method: "DELETE"} = conn, state) do
    send(state.owner, {:remote_mcp_wire_delete, get_req_header(conn, "mcp-session-id")})

    if authorized?(conn, state.authorization) and
         Enum.all?(state.headers, fn {name, value} -> get_req_header(conn, name) == [value] end),
       do: send_resp(conn, 200, ""),
       else: send_resp(conn, 401, "unauthorized")
  end

  defp hold_stream(conn, owner) do
    conn = conn |> put_resp_content_type("text/event-stream") |> send_chunked(200)
    {:ok, conn} = chunk(conn, ": stream ready\n\n")
    monitor = Process.monitor(owner)
    reference = make_ref()
    send(owner, {:remote_mcp_wire_stream_open, self(), reference})

    receive do
      {:release_remote_mcp_wire_stream, ^reference} ->
        Process.demonitor(monitor, [:flush])
        send(owner, {:remote_mcp_wire_stream_released, reference})

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        :ok
    after
      30_000 ->
        Process.demonitor(monitor, [:flush])
        send(owner, {:remote_mcp_wire_stream_timeout, reference})
    end

    conn
  end

  defp respond(conn, _request, %{redirect_to: redirect_to}) when is_binary(redirect_to) do
    conn
    |> put_resp_header("location", redirect_to)
    |> send_resp(307, "")
  end

  defp respond(conn, request, state) do
    if authorized?(conn, state.authorization) and
         Enum.all?(state.headers, fn {name, value} -> get_req_header(conn, name) == [value] end) do
      if state.hold_invocation and request["method"] == "tools/call" do
        hold_invocation(conn, request, state)
      else
        session_id =
          if request["method"] == "initialize" do
            if state.hold_initialization, do: hold_initialization(state.owner)
            value = "wire-session-#{System.unique_integer([:positive, :monotonic])}"
            send(state.owner, {:remote_mcp_wire_initialized, value})
            value
          else
            state.session_id
          end

        protocol_response(conn, request, session_id)
      end
    else
      send_resp(conn, 401, "unauthorized")
    end
  end

  defp hold_initialization(owner) do
    reference = make_ref()
    monitor = Process.monitor(owner)
    send(owner, {:remote_mcp_wire_initialization_held, self(), reference})

    receive do
      {:release_remote_mcp_initialization, ^reference} -> :ok
      {:DOWN, ^monitor, :process, ^owner, _reason} -> :ok
    after
      5_000 -> :ok
    end

    Process.demonitor(monitor, [:flush])
  end

  defp hold_invocation(conn, request, state) do
    owner = state.owner
    monitor = Process.monitor(owner)
    reference = make_ref()
    send(owner, {:remote_mcp_wire_invocation_held, self(), reference, request["id"]})

    result =
      receive do
        {:release_remote_mcp_wire_invocation, ^reference} ->
          send(owner, {:remote_mcp_wire_invocation_released, reference})
          protocol_response(conn, request, state.session_id)

        {:cancel_remote_mcp_wire_invocation, ^reference} ->
          send_resp(conn, 503, "cancelled")

        {:DOWN, ^monitor, :process, ^owner, _reason} ->
          send_resp(conn, 503, "cancelled")
      after
        30_000 ->
          send(owner, {:remote_mcp_wire_invocation_timeout, reference})
          send_resp(conn, 503, "timed out")
      end

    Process.demonitor(monitor, [:flush])
    result
  end

  defp protocol_response(conn, %{"method" => "initialize", "id" => id}, session_id) do
    result = %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "vxpipe-engine-wire-fixture", "version" => "1"}
    }

    conn
    |> put_resp_header("mcp-session-id", session_id)
    |> json_response(200, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp protocol_response(
         conn,
         %{"method" => "notifications/initialized"},
         _session_id
       ) do
    send_resp(conn, 202, "")
  end

  defp protocol_response(conn, %{"method" => "tools/list", "id" => id}, _session_id) do
    result = %{"tools" => [tool_descriptor()]}
    json_response(conn, 200, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  defp protocol_response(
         conn,
         %{
           "method" => "tools/call",
           "id" => id,
           "params" => %{"arguments" => %{"customer_id" => "slow"}}
         },
         _session_id
       ) do
    receive do
      :release_remote_mcp_wire_response -> success(conn, id, "found slow")
    after
      500 -> success(conn, id, "found slow")
    end
  end

  defp protocol_response(
         conn,
         %{
           "method" => "tools/call",
           "id" => id,
           "params" => %{"arguments" => %{"customer_id" => "oversized"}}
         },
         _session_id
       ) do
    success(conn, id, String.duplicate("x", 2_000))
  end

  defp protocol_response(
         conn,
         %{
           "method" => "tools/call",
           "id" => id,
           "params" => %{"arguments" => %{"customer_id" => customer_id}}
         },
         _session_id
       ) do
    success(conn, id, "found #{customer_id}")
  end

  defp protocol_response(conn, _request, _session_id), do: send_resp(conn, 400, "unsupported")

  defp success(conn, id, text) do
    json_response(conn, 200, %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{"content" => [%{"type" => "text", "text" => text}]}
    })
  end

  defp tool_descriptor do
    %{
      "name" => "lookup_customer",
      "description" => "Looks up one controlled fixture customer.",
      "inputSchema" => %{
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "properties" => %{"customer_id" => %{"type" => "string"}},
        "required" => ["customer_id"],
        "additionalProperties" => false
      }
    }
  end

  defp authorized?(_conn, nil), do: true
  defp authorized?(conn, expected), do: authorization(conn) == expected

  defp authorization(conn) do
    case get_req_header(conn, "authorization") do
      [value] -> value
      _missing_or_repeated -> nil
    end
  end

  defp json_response(conn, status, payload) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(payload))
  end
end
