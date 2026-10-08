defmodule Vxpipe.CallEngine.ModelCatalog do
  @moduledoc "Installed provider and public model listings for call-spec capabilities."

  alias Vxpipe.Providers.Registry

  @capabilities %{
    "speech_to_text" => :stt,
    "output_speech_to_text" => :stt,
    "text_to_speech" => :tts,
    "speech_to_speech" => :sts,
    "model_inference" => :llm
  }
  @names %{
    "cartesia" => "Cartesia",
    "deepgram" => "Deepgram",
    "deepseek" => "DeepSeek",
    "elevenlabs" => "ElevenLabs",
    "fireworks" => "Fireworks",
    "google" => "Google",
    "morse" => "Morse",
    "openai" => "OpenAI",
    "openrouter" => "OpenRouter",
    "rime" => "Rime",
    "zenmux" => "Zenmux"
  }

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
        |> Enum.map(fn {id, _capabilities} -> %{id: id, name: Map.get(@names, id, id)} end)
        |> Enum.sort_by(& &1.id)

      {:ok, providers}
    end
  end

  def models(provider, capability) do
    with {:ok, kind} <- kind(capability),
         {:ok, adapter} <- Registry.resolve_capability(provider, kind) do
      if kind == :llm,
        do: Vxpipe.AgentRuntime.ModelCatalog.models(provider),
        else: {:ok, adapter.models()}
    end
  end

  defp kind(capability) do
    case Map.fetch(@capabilities, capability) do
      {:ok, kind} -> {:ok, kind}
      :error -> {:error, :invalid_capability}
    end
  end
end
