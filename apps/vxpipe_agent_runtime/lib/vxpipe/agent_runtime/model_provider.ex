defmodule Vxpipe.AgentRuntime.ModelProvider do
  @moduledoc "The provider boundary used by a runtime request worker."

  alias Vxpipe.AgentRuntime.{ModelRequest, ModelResponse}

  @callback generate(model :: term(), ModelRequest.t()) ::
              {:ok, ModelResponse.t()} | {:error, atom()}

  @callback stream(
              model :: term(),
              ModelRequest.t(),
              emit :: (String.t() -> :ok | {:error, atom()})
            ) :: {:ok, ModelResponse.t()} | {:error, atom()}

  @optional_callbacks stream: 3
end
