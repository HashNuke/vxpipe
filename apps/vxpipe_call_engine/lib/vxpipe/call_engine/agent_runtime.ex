defmodule Vxpipe.CallEngine.AgentRuntime do
  @moduledoc false

  @type server :: GenServer.server()

  @callback ask(server(), String.t(), keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback cancel(server(), String.t(), atom()) :: :ok | {:error, term()}

  @callback discard_requests(server(), [String.t()]) :: :ok | {:error, term()}
end
