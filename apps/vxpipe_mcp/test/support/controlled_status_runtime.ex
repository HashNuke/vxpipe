defmodule Vxpipe.MCP.ControlledStatusRuntime do
  @moduledoc false
  @behaviour Vxpipe.MCP.ClientRuntime

  @impl true
  def child_spec(opts), do: {Vxpipe.MCP.ReadyClient, opts}

  @impl true
  def status(client) do
    with {:ok, %{status_callback: callback}} <- Vxpipe.MCP.ReadyClient.status(client) do
      callback.()
    end
  end
end
