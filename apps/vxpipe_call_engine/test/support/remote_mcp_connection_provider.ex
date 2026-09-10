defmodule Vxpipe.CallEngine.TestRemoteMCPConnectionProvider do
  @moduledoc false

  alias Vxpipe.MCP.Connection

  def open(key, config) do
    observer = Keyword.fetch!(config, :test_observer)
    client = Keyword.fetch!(config, :test_client)
    send(observer, {:test_remote_mcp_opened, key, config})
    {:ok, Connection.new(key, self(), client)}
  end
end
