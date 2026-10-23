defmodule Vxpipe.Gateway.Test.MCPProbeHandler do
  @moduledoc false
  use ExMCP.Server.Handler

  @impl GenServer
  def init(options), do: {:ok, options}

  @impl ExMCP.Server.Handler
  def handle_initialize(_params, state) do
    {:ok,
     %{
       protocolVersion: "2025-11-25",
       capabilities: %{tools: %{}},
       serverInfo: %{name: "vxpipe-probe", version: "1"}
     }, state}
  end

  @impl ExMCP.Server.Handler
  def handle_list_tools(_cursor, state) do
    send(state.owner, {:probe_actor, state.actor})

    if state.block do
      send(state.owner, {:probe_blocked, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, [], nil, state}
  end

  @impl ExMCP.Server.Handler
  def handle_call_tool(_name, _arguments, state) do
    {:error, ExMCP.Error.protocol_error(-32602, "Tool unavailable"), state}
  end
end
