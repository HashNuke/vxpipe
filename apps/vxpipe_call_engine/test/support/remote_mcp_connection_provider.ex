defmodule Vxpipe.CallEngine.TestRemoteMCPConnectionProvider do
  @moduledoc false

  alias Vxpipe.MCP.Connection

  def open(key, config) do
    observer = Keyword.fetch!(config, :test_observer)
    client = Keyword.fetch!(config, :test_client)
    send(observer, {:test_remote_mcp_opened, key, config})

    if Keyword.get(config, :test_gate_initialization, false) do
      send(observer, {:test_remote_mcp_initializing, self()})

      receive do
        :test_remote_mcp_initialized -> :ok
      end
    end

    {:ok, Connection.new(key, self(), client)}
  end
end
