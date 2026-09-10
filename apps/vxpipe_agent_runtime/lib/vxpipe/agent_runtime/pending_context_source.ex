defmodule Vxpipe.AgentRuntime.PendingContextSource do
  @moduledoc "The host boundary for current unresolved tool-invocation projections."

  alias Vxpipe.AgentRuntime.PendingInvocation

  @callback snapshot(
              source :: term(),
              correlation :: map(),
              timeout_ms :: pos_integer()
            ) :: {:ok, [PendingInvocation.t()]} | {:error, atom()}
end
