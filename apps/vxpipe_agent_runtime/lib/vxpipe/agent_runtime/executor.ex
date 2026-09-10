defmodule Vxpipe.AgentRuntime.Executor do
  @moduledoc "The private tool-execution boundary implemented by a runtime host."

  @callback execute(
              binding :: term(),
              arguments :: map(),
              context :: map(),
              invocation_id :: String.t()
            ) :: {:ok, term()} | {:error, atom()}
end
