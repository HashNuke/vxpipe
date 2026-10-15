defmodule Vxpipe.Gateway.MCP.Handler do
  @moduledoc "MCP protocol callbacks over the operations enabled by Vxpipe."
  use ExMCP.Server.Handler

  alias Vxpipe.Gateway.MCP.{Protocol, Tools}

  def options(conn, _request),
    do: %{actor: conn.assigns.mcp_actor, call_options: conn.assigns.mcp_call_options}

  @impl GenServer
  def init(%{actor: _actor, call_options: _options} = state), do: {:ok, state}

  @impl GenServer
  def format_status(status),
    do: Map.merge(status, %{state: :redacted, message: :redacted, reason: :redacted, log: []})

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
  def handle_list_tools(nil, state), do: {:ok, Tools.list(state.actor), nil, state}

  def handle_list_tools(_cursor, state),
    do: {:error, ExMCP.Error.protocol_error(-32602, "Invalid cursor"), state}

  @impl ExMCP.Server.Handler
  def handle_call_tool(name, arguments, state) do
    # ExMCP merges request metadata into callback arguments. The HTTP boundary has
    # already rejected it as a user argument; it is not part of a product operation.
    arguments = Map.delete(arguments, "_meta")

    with {:ok, arguments} <- Tools.authorize(state.actor, name, arguments),
         {:ok, result} <- Tools.call(state.actor, name, arguments, state.call_options) do
      {:ok, result(result, false), state}
    else
      {:error, :invalid_tool_arguments} ->
        {:error, ExMCP.Error.protocol_error(-32602, "Invalid tool arguments"), state}

      {:error, reason} ->
        {:ok, result(%{error: Tools.error(name, reason)}, true), state}
    end
  rescue
    _exception -> internal_error(state)
  catch
    _kind, _reason -> internal_error(state)
  end

  @impl ExMCP.Server.Handler
  def handle_set_log_level(_level, state),
    do: {:error, ExMCP.Error.protocol_error(-32601, "Method not found"), state}

  defp result(value, error?),
    do: %{
      content: [%{type: "text", text: JSON.encode!(value)}],
      structuredContent: value,
      isError: error?
    }

  defp internal_error(state),
    do: {:error, ExMCP.Error.protocol_error(-32603, "Operation failed"), state}
end
