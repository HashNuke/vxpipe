defmodule Vxpipe.Providers.Deepgram.Speech do
  @moduledoc "Deepgram selection and runtime-setting validation for CallEngine."

  alias Vxpipe.Providers.Deepgram

  def selection_options(model, input) when is_map(input) do
    with {:ok, options} <- normalize(input),
         {:ok, encoding} <- encoding(Keyword.get(options, :encoding)) do
      {:ok, options |> Keyword.put(:encoding, encoding) |> Keyword.put(:model, model)}
    end
  end

  def selection_options(_model, _input), do: {:error, :unsupported_capability}

  def settings(:speech_to_text, settings) do
    Keyword.validate(settings,
      enabled: false,
      media_ingress: nil,
      wire_module: Deepgram.STTSocket,
      wire_options: []
    )
  end

  def settings(:text_to_speech, settings) do
    Keyword.validate(settings,
      enabled: false,
      maximum_requests: nil,
      wire_module: Deepgram.TTSSocket,
      wire_options: []
    )
  end

  defp normalize(input) do
    Enum.reduce_while(input, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case key do
        "encoding" -> {:cont, {:ok, [{:encoding, value} | acc]}}
        "sample_rate" -> {:cont, {:ok, [{:sample_rate, value} | acc]}}
        _invalid -> {:halt, {:error, :unsupported_capability}}
      end
    end)
  end

  defp encoding("opus"), do: {:ok, :opus}
  defp encoding("linear16"), do: {:ok, :linear16}
  defp encoding(_value), do: {:error, :unsupported_capability}
end
