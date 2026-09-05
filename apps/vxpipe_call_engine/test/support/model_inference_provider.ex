defmodule Vxpipe.CallEngine.TestModelInferenceProvider do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.ModelInference

  def new(options) do
    case Keyword.fetch(options, :observer) do
      {:ok, observer} when is_pid(observer) ->
        {:ok, %{observer: observer, streaming: Keyword.get(options, :streaming, false)}}

      _missing_or_invalid ->
        {:error, :invalid_configuration}
    end
  end

  def generate(%{observer: observer}, messages, definitions) do
    notify_request(observer, :test_model_inference_request, messages, definitions)

    receive do
      {:test_model_inference_reply, result} -> result
    end
  end

  def streaming?(config), do: Map.get(config, :streaming, false)

  def stream(%{observer: observer}, messages, definitions, emit) do
    notify_request(observer, :test_stream_model_inference_request, messages, definitions)
    stream_loop(emit)
  end

  defp notify_request(observer, tag, messages, []) do
    send(observer, {tag, self(), messages})
  end

  defp notify_request(observer, tag, messages, definitions) do
    send(observer, {tag, self(), messages, definitions})
  end

  defp stream_loop(emit) do
    receive do
      {:test_model_inference_chunk, chunk, caller} ->
        result = emit.(chunk)
        send(caller, {:test_model_inference_chunk_result, result})

        case result do
          :ok -> stream_loop(emit)
          {:error, reason} -> {:error, reason}
        end

      {:test_model_inference_reply, result} ->
        result
    end
  end
end
