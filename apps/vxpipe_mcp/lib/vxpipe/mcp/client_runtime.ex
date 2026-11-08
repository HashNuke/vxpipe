defmodule Vxpipe.MCP.ClientRuntime do
  @moduledoc false

  @callback child_spec(keyword()) :: Supervisor.child_spec()
  @callback status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  @callback close(GenServer.server(), reference(), non_neg_integer()) :: :ok
  @optional_callbacks close: 3
end
