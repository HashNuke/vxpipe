defmodule Vxpipe.CallEngine.ModelCatalog do
  @moduledoc "Installed provider and public model listings for call-spec capabilities."

  alias Vxpipe.Providers.Registry

  @capabilities %{
    "speech_to_text" => :stt,
    "output_speech_to_text" => :stt,
    "text_to_speech" => :tts,
    "speech_to_speech" => :sts,
    "model_inference" => :llm,
    "decisions" => :decisions
  }
  @names %{
    "cartesia" => "Cartesia",
    "deepgram" => "Deepgram",
    "deepseek" => "DeepSeek",
    "elevenlabs" => "ElevenLabs",
    "fireworks" => "Fireworks",
    "google" => "Google",
    "jev" => "TypeSafe",
    "morse" => "MorseCode Local",
    "morse_code_api" => "MorseCode API",
    "openai" => "OpenAI",
    "openrouter" => "OpenRouter",
    "rime" => "Rime",
    "zenmux" => "Zenmux",
    "telnyx" => "Telnyx",
    "twilio" => "Twilio"
  }

  def provider_name(id), do: Map.get(@names, id, id)

  def catalog do
    Map.new(@capabilities, fn {capability, _kind} ->
      {:ok, providers} = providers(capability)

      listings =
        Map.new(providers, fn provider ->
          {:ok, models} = models(provider.id, capability)
          {provider.id, models}
        end)

      {capability, listings}
    end)
  end

  def providers(capability) do
    with {:ok, kind} <- kind(capability) do
      providers =
        Registry.catalog()
        |> Enum.filter(fn {provider, capabilities} ->
          kind in capabilities and
            match?({:ok, _module}, Registry.resolve_capability(provider, kind))
        end)
        |> Enum.map(fn {id, _capabilities} -> %{id: id, name: provider_name(id)} end)
        |> Enum.sort_by(& &1.id)

      {:ok, providers}
    end
  end

  def models(provider, "decisions") do
    with {:ok, adapter} <- Registry.resolve_capability(provider, :decisions) do
      models =
        adapter.models()
        |> Enum.sort()
        |> Enum.with_index()
        |> Enum.map(fn {id, index} ->
          %{id: id, name: decisions_model_name(provider, id), default: index == 0, voices: nil}
        end)

      {:ok, models}
    else
      _invalid -> {:error, :unsupported_provider_capability}
    end
  end

  def models(provider, capability) do
    with {:ok, kind} <- kind(capability),
         {:ok, adapter} <- Registry.resolve_capability(provider, kind) do
      if kind == :llm,
        do: Vxpipe.AgentRuntime.ModelCatalog.models(provider),
        else: {:ok, Enum.map(adapter.models(), &language_descriptor(&1, kind, provider))}
    end
  end

  defp language_descriptor(model, kind, provider) do
    case Vxpipe.CallEngine.Speech.ModelLanguages.descriptor(kind, provider, model.id) do
      nil -> model
      descriptor -> Map.put(model, :languages, descriptor)
    end
  end

  defp decisions_model_name("openai", "gpt-6-luna"), do: "GPT-6 Luna"
  defp decisions_model_name("jev", "jev-1.14.0"), do: "Jev 1.14.0"
  defp decisions_model_name("jev", "jev-latest"), do: "Jev Latest"
  defp decisions_model_name(_provider, id), do: id

  defp kind(capability) do
    case Map.fetch(@capabilities, capability) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_capability}
    end
  end
end
