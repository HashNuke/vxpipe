defmodule Vxpipe.MCP.ReadyClientRuntime do
  @moduledoc false

  @behaviour Vxpipe.MCP.ClientRuntime

  @impl true
  def child_spec(opts), do: {Vxpipe.MCP.ReadyClient, opts}

  @impl true
  def status(client), do: Vxpipe.MCP.ReadyClient.status(client)
end
