defmodule Vxpipe.MCP.ClientRuntime do
  @moduledoc false

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback status(GenServer.server()) :: {:ok, map()} | {:error, term()}
end
