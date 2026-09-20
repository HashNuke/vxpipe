defmodule Vxpipe.CallEngine.CapabilityCatalog do
  @moduledoc "Closed mapping from inline capability selections to internal adapters."

  alias Vxpipe.CallEngine.CallSpec.CapabilitySelection
  alias Vxpipe.CallEngine.Provider.{Deepgram, MorseCode}

  @speech_keys [:encoding, :sample_rate]
  @morse_keys [
    :amplitude,
    :detection_threshold,
    :end_gap_units,
    :frequency_hz,
    :frequency_tolerance_hz,
    :maximum_audio_bytes,
    :maximum_text_bytes,
    :maximum_utterance_ms,
    :sample_rate,
    :unit_duration_ms,
    :window_duration_ms
  ]

  def validate(%CapabilitySelection{kind: :model_inference, provider: provider} = selection)
      when provider in ["google", "zenmux"] do
    case Vxpipe.AgentRuntime.ProviderSelection.translate(
           selection.provider,
           selection.model,
           selection.options,
           selection.provider_options
         ) do
      {:ok, _options} -> :ok
      {:error, _reason} -> {:error, :unsupported_capability}
    end
  end

  def validate(%CapabilitySelection{
        kind: :model_inference,
        provider: "fixture",
        credential_name: nil,
        options: options,
        provider_options: specific
      })
      when map_size(options) == 0 and map_size(specific) == 0, do: :ok

  def validate(%CapabilitySelection{provider_options: specific} = selection)
      when map_size(specific) == 0 do
    with {:ok, options} <- speech_options(selection) do
      validate_speech(selection, options)
    end
  end

  def validate(_selection), do: {:error, :unsupported_capability}

  def adapter(%CapabilitySelection{kind: :model_inference, provider: provider})
      when provider in ["google", "zenmux"],
      do: {:ok, Vxpipe.AgentRuntime.Provider.ReqLLM}

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "deepgram"}),
    do: {:ok, Deepgram.Flux.Session}

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "deepgram"}),
    do: {:ok, Deepgram.FluxTextToSpeech}

  def adapter(%CapabilitySelection{kind: :speech_to_text, provider: "morse"}),
    do: {:ok, Vxpipe.CallEngine.Provider.MorseCodeSTT.Session}

  def adapter(%CapabilitySelection{kind: :text_to_speech, provider: "morse"}),
    do: {:ok, Vxpipe.CallEngine.Provider.MorseCodeTTS}

  def adapter(_selection), do: {:error, :unsupported_capability}

  def credential_required?(%CapabilitySelection{provider: provider}),
    do: provider not in ["fixture", "morse"]

  def speech_options(%CapabilitySelection{provider: "deepgram", model: model, options: input}) do
    with {:ok, options} <- normalize(input, @speech_keys),
         {:ok, encoding} <- encoding(Keyword.get(options, :encoding)) do
      {:ok, options |> Keyword.put(:encoding, encoding) |> Keyword.put(:model, model)}
    end
  end

  def speech_options(%CapabilitySelection{provider: "morse", model: "morse", options: input}),
    do: normalize(input, @morse_keys)

  def speech_options(_selection), do: {:error, :unsupported_capability}

  defp validate_speech(%{provider: "morse", credential_name: nil, kind: kind}, options)
       when kind in [:speech_to_text, :text_to_speech] do
    case MorseCode.Config.new(options) do
      {:ok, _config} -> :ok
      {:error, _reason} -> {:error, :unsupported_capability}
    end
  end

  defp validate_speech(%{provider: "deepgram", kind: :speech_to_text}, options),
    do: Deepgram.Flux.validate_options(options)

  defp validate_speech(%{provider: "deepgram", kind: :text_to_speech}, options),
    do: Deepgram.FluxTextToSpeech.validate_options(options)

  defp validate_speech(_selection, _options), do: {:error, :unsupported_capability}

  defp normalize(input, allowed) when is_map(input) do
    Enum.reduce_while(input, {:ok, []}, fn {key, value}, {:ok, acc} ->
      case Enum.find(allowed, &(Atom.to_string(&1) == key)) do
        nil -> {:halt, {:error, :unsupported_capability}}
        key -> {:cont, {:ok, [{key, value} | acc]}}
      end
    end)
  end

  defp normalize(_input, _allowed), do: {:error, :unsupported_capability}
  defp encoding("opus"), do: {:ok, :opus}
  defp encoding("linear16"), do: {:ok, :linear16}
  defp encoding(_value), do: {:error, :unsupported_capability}
end
