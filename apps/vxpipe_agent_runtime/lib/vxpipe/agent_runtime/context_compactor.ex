defmodule Vxpipe.AgentRuntime.ContextCompactor do
  @moduledoc "Produces one bounded summary from selected authorized history."

  alias Vxpipe.AgentRuntime.{CompactionRequest, CompactionResult}

  @callback compact(state :: term(), CompactionRequest.t()) ::
              {:ok, CompactionResult.t()} | {:error, term()}
end
