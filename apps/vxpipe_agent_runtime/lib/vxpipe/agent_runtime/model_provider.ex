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

  @callback streaming?(model :: term()) :: boolean()

  @callback context_window_tokens(model :: term()) :: pos_integer() | nil

  @callback maximum_output_tokens(model :: term()) :: pos_integer() | nil

  @optional_callbacks stream: 3,
                      streaming?: 1,
                      context_window_tokens: 1,
                      maximum_output_tokens: 1
end
