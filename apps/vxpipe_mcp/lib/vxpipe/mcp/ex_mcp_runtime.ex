defmodule Vxpipe.MCP.ExMCPRuntime do
  @moduledoc false

  @behaviour Vxpipe.MCP.ClientRuntime

  @impl true
  def child_spec(opts), do: {ExMCP.Client, opts}

  @impl true
  def status(client), do: ExMCP.Client.get_status(client)

  @impl true
  def close(client, permission, timeout),
    do: ExMCP.Client.disconnect(client, permission, timeout)
end
