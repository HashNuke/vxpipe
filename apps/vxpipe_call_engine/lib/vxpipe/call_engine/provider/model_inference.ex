defmodule Vxpipe.CallEngine.Provider.ModelInference do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.ModelInference.Message
  alias Vxpipe.CallEngine.Tool.{Call, Definition}

  @callback new(keyword()) :: {:ok, term()} | {:error, atom()}
  @callback generate(term(), [Message.t()], [Definition.t()]) ::
              {:ok, String.t()} | {:tool_calls, [Call.t()]} | {:error, atom()}
  @callback streaming?(term()) :: boolean()
  @callback stream(
              term(),
              [Message.t()],
              [Definition.t()],
              (String.t() -> :ok | {:error, atom()})
            ) :: :ok | {:tool_calls, [Call.t()]} | {:error, atom()}

  @optional_callbacks streaming?: 1, stream: 4
end
