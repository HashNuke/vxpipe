defmodule Vxpipe.Providers.Registry do
  @moduledoc "Fixed, exact provider capability catalog."

  @providers %{
    "cartesia" => Vxpipe.Providers.Cartesia,
    "deepseek" => Vxpipe.Providers.DeepSeek,
    "openrouter" => Vxpipe.Providers.OpenRouter,
    "fireworks" => Vxpipe.Providers.Fireworks,
    "deepgram" => Vxpipe.Providers.Deepgram,
    "google" => Vxpipe.Providers.Google,
    "morse" => Vxpipe.Providers.MorseCode,
    "openai" => Vxpipe.Providers.OpenAI,
    "rime" => Vxpipe.Providers.Rime,
    "telnyx" => Vxpipe.Providers.Telnyx,
    "twilio" => Vxpipe.Providers.Twilio,
    "zenmux" => Vxpipe.Providers.Zenmux
  }

  @spec fetch(term()) :: {:ok, module()} | {:error, :unsupported_provider}
  def fetch(provider) do
    case Map.fetch(@providers, provider) do
      {:ok, manifest} -> {:ok, manifest}
      :error -> {:error, :unsupported_provider}
    end
  end

  @spec fetch_capability(term(), term()) ::
          {:ok, module()} | {:error, :unsupported_provider | :unsupported_provider_capability}
  def fetch_capability(provider, capability) do
    with {:ok, manifest} <- fetch(provider) do
      case Map.fetch(manifest.capabilities(), capability) do
        {:ok, implementation} -> {:ok, implementation}
        :error -> {:error, :unsupported_provider_capability}
      end
    end
  end

  @doc "Resolves a declared capability only when its owning application is installed."
  @spec resolve_capability(term(), term()) ::
          {:ok, module()}
          | {:error,
             :unsupported_provider
             | :unsupported_provider_capability
             | :provider_implementation_unavailable}
  def resolve_capability(provider, capability) do
    with {:ok, implementation} <- fetch_capability(provider, capability) do
      if Code.ensure_loaded?(implementation),
        do: {:ok, implementation},
        else: {:error, :provider_implementation_unavailable}
    end
  end

  @spec catalog() :: %{String.t() => [Vxpipe.Providers.capability()]}
  def catalog do
    Map.new(@providers, fn {id, manifest} ->
      {id, manifest.capabilities() |> Map.keys() |> Enum.sort()}
    end)
  end
end
