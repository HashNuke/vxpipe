defmodule Vxpipe.MCP.CheckFixtureRuntime do
  @moduledoc false
  @behaviour Vxpipe.MCP.ClientRuntime

  @impl true
  def child_spec(options), do: {Vxpipe.MCP.CheckClientFixture, options}

  @impl true
  def status(client), do: GenServer.call(client, :get_status)
end
