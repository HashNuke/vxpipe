defmodule Vxpipe.CallEngine.Provider.ModelInference do
  @moduledoc false

  alias Vxpipe.CallEngine.Provider.ModelInference.Message

  @callback new(keyword()) :: {:ok, term()} | {:error, atom()}
  @callback generate(term(), [Message.t()]) :: {:ok, String.t()} | {:error, atom()}
end
