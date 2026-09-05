defmodule Vxpipe.CallEngine.Provider.ModelInference do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.ModelInference.Message

  @callback new(keyword()) :: {:ok, term()} | {:error, atom()}
  @callback generate(term(), [Message.t()]) :: {:ok, String.t()} | {:error, atom()}
  @callback streaming?(term()) :: boolean()
  @callback stream(term(), [Message.t()], (String.t() -> :ok | {:error, atom()})) ::
              :ok | {:error, atom()}

  @optional_callbacks streaming?: 1, stream: 3
end
