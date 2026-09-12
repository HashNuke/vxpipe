defmodule Vxpipe.AgentRuntime.ContextCompactor do
  @moduledoc "Produces one bounded summary from selected authorized history."

  alias Vxpipe.AgentRuntime.{CompactionObservation, CompactionRequest, CompactionResult}

  @callback compact(state :: term(), CompactionRequest.t()) ::
              {:ok, CompactionResult.t()}
              | {:error, term()}
              | {:error, term(), CompactionObservation.t()}
end
