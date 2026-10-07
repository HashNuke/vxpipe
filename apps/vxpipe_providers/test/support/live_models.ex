defmodule Vxpipe.Providers.LiveModels do
  @moduledoc "Reviewed, fixed models for the opt-in provider acceptance lane."

  @models %{
    "zenmux" => %{model: "openai/gpt-4o", env: "ZENMUX_API_KEY", specific: %{}},
    "google" => %{model: "gemini-3.5-flash-lite", env: "GEMINI_API_KEY", specific: %{}},
    "openai" => %{model: "gpt-6-luna", env: "OPENAI_API_KEY", specific: %{}},
    "deepseek" => %{
      model: "deepseek-flash",
      env: "DEEPSEEK_API_KEY",
      specific: %{"thinking" => "disabled"}
    },
    "openrouter" => %{
      model: "google/gemini-3.5-flash-lite",
      env: "OPENROUTER_API_KEY",
      specific: %{}
    },
    "fireworks" => %{
      model: "accounts/fireworks/models/nemotron-lightning-3p5-30b-a3b",
      env: "FIREWORKS_API_KEY",
      specific: %{}
    }
  }

  @speech %{
    "google" => %{sts: "gemini-3.8-live"},
    "elevenlabs" => %{
      stt: "scribe_v2_realtime",
      sts_backend: "gemini-3.5-flash-lite",
      sts_tts: "eleven_v4_turbo",
      tts: "eleven_flash_v2_5",
      tts_voice: "JBFqnCBsd6RMkjVDRZzb"
    },
    "cartesia" => %{
      stt: "ink-2",
      tts: "sonic-3.6",
      tts_voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"
    },
    "deepgram" => %{
      stt: "flux-general-multi",
      stt_en: "flux-general-en",
      tts: "flux-haley-en",
      fixture_tts: "aura-2-thalia-en"
    },
    "openai" => %{sts: "gpt-live-1", backend: "gpt-6-luna"}
  }

  def llm(provider), do: Map.fetch!(@models, provider)
  def speech(provider, kind), do: @speech |> Map.fetch!(provider) |> Map.fetch!(kind)
end
