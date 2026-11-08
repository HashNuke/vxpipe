defmodule Vxpipe.CallEngine.RemoteMCPWireConnectionProvider do
  @moduledoc false

  alias Vxpipe.MCP.Connections

  def open(key, config, options \\ []), do: Connections.open_loopback_test(key, config, options)
end
