defmodule Vxpipe.AgentRuntime.ModelProvider do
  @moduledoc "The provider boundary used by a runtime request worker."

  alias Vxpipe.AgentRuntime.{ModelRequest, ModelResponse}

  @doc """
  Reports validated local/client initialization without generation or external work.

  This callback runs in the session's bounded readiness query and must not block or perform I/O.
  Providers with asynchronous initialization inspect their existing local acknowledgement state.
  Missing contracts fail readiness closed; they do not change ordinary request compatibility.
  """
  @callback readiness(model :: term()) :: Vxpipe.AgentRuntime.Readiness.status()

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

  @optional_callbacks readiness: 1,
                      stream: 3,
                      streaming?: 1,
                      context_window_tokens: 1,
                      maximum_output_tokens: 1
end
