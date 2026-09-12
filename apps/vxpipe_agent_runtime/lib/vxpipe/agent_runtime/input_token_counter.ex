defmodule Vxpipe.AgentRuntime.InputTokenCounter do
  @moduledoc "Measures the complete normalized input for one model request."

  alias Vxpipe.AgentRuntime.ModelRequest

  @callback count(state :: term(), ModelRequest.t()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
