defmodule Vxpipe.Providers.Deepgram.Speech do
  @moduledoc "Deepgram selection and runtime-setting validation for CallEngine."

  alias Vxpipe.Providers.Deepgram

  def selection_options(:speech_to_text, model, input) when is_map(input) do
    with {:ok, options} <- normalize(input),
         {:ok, encoding} <- encoding(Keyword.get(options, :encoding)) do
      {:ok, options |> Keyword.put(:encoding, encoding) |> Keyword.put(:model, model)}
    end
  end

  def selection_options(:text_to_speech, "flux", input) when is_map(input) do
    with {:ok, options} <- normalize(input, [:voice]),
         {:ok, model} <- Deepgram.FluxTextToSpeech.model_for_voice(Keyword.get(options, :voice)),
         {:ok, encoding} <- encoding(Keyword.get(options, :encoding, "linear16")) do
      {:ok,
       options
       |> Keyword.delete(:voice)
       |> Keyword.put(:encoding, encoding)
       |> Keyword.put(:model, model)}
    end
  end

  def selection_options(:text_to_speech, model, input) when is_map(input) do
    with {:ok, options} <- normalize(input),
         {:ok, encoding} <- encoding(Keyword.get(options, :encoding)) do
      {:ok, options |> Keyword.put(:encoding, encoding) |> Keyword.put(:model, model)}
    end
  end

  def selection_options(_kind, _model, _input), do: {:error, :unsupported_capability}

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

  defp normalize(input, additional \\ []) do
    Enum.reduce_while(input, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case key do
        "encoding" ->
          {:cont, {:ok, [{:encoding, value} | acc]}}

        "sample_rate" ->
          {:cont, {:ok, [{:sample_rate, value} | acc]}}

        "voice" ->
          if :voice in additional,
            do: {:cont, {:ok, [{:voice, value} | acc]}},
            else: {:halt, {:error, :unsupported_capability}}

        _invalid ->
          {:halt, {:error, :unsupported_capability}}
      end
    end)
  end

  defp encoding("opus"), do: {:ok, :opus}
  defp encoding("linear16"), do: {:ok, :linear16}
  defp encoding(_value), do: {:error, :unsupported_capability}
end
