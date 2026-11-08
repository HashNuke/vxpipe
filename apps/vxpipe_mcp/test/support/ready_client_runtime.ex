defmodule Vxpipe.MCP.ReadyClientRuntime do
  @moduledoc false

  @behaviour Vxpipe.MCP.ClientRuntime

  @impl true
  def child_spec(opts) do
    if observer = Keyword.get(opts, :test_spec_observer) do
      send(observer, {:pending_integration, self()})
      receive do: (:release_spec -> :ok)
    end

    {Vxpipe.MCP.ReadyClient, opts}
  end

  @impl true
  def status(client), do: Vxpipe.MCP.ReadyClient.status(client)
end
