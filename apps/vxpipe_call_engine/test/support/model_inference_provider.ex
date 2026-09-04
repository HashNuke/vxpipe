defmodule Vxpipe.CallEngine.TestModelInferenceProvider do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.ModelInference

  def new(options) do
    case Keyword.fetch(options, :observer) do
      {:ok, observer} when is_pid(observer) -> {:ok, %{observer: observer}}
      _missing_or_invalid -> {:error, :invalid_configuration}
    end
  end

  def generate(%{observer: observer}, messages) do
    send(observer, {:test_model_inference_request, self(), messages})

    receive do
      {:test_model_inference_reply, result} -> result
    end
  end
end
