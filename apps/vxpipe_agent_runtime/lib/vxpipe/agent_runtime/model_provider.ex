defmodule Vxpipe.AgentRuntime.ModelProvider do
  @moduledoc "The provider boundary used by a runtime request worker."

  alias Vxpipe.AgentRuntime.Request

  @callback generate(model :: term(), Request.t()) ::
              {:ok, String.t()} | {:error, atom()}
end
