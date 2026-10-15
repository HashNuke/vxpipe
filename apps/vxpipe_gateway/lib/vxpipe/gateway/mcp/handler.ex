defmodule Vxpipe.Gateway.MCP.Handler do
  @moduledoc "MCP protocol callbacks over the operations enabled by Vxpipe."
  use ExMCP.Server.Handler

  alias Vxpipe.Gateway.MCP.Protocol

  def options(conn, _request), do: %{actor: conn.assigns.mcp_actor}

  @impl GenServer
  def init(%{actor: actor}), do: {:ok, %{actor: actor}}

  @impl ExMCP.Server.Handler
  def handle_initialize(_params, state) do
    {:ok,
     %{
       protocolVersion: Protocol.version(),
       capabilities: %{tools: %{}},
       serverInfo: %{name: "vxpipe", version: "0.1.0"}
     }, state}
  end

  @impl ExMCP.Server.Handler
  def handle_list_tools(_cursor, state), do: {:ok, [], nil, state}

  @impl ExMCP.Server.Handler
  def handle_call_tool(_name, _arguments, state),
    do: {:error, ExMCP.Error.protocol_error(-32602, "Tool unavailable"), state}

  @impl ExMCP.Server.Handler
  def handle_set_log_level(_level, state),
    do: {:error, ExMCP.Error.protocol_error(-32601, "Method not found"), state}
end
