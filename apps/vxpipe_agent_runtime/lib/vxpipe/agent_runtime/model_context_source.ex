defmodule Vxpipe.AgentRuntime.ModelContextSource do
  @moduledoc "The host boundary for trusted transient model context."

  @callback snapshot(
              source :: term(),
              correlation :: map(),
              timeout_ms :: pos_integer()
            ) :: {:ok, map()} | {:error, atom()}
end
