defmodule Vxpipe.Providers.ElevenLabs do
  @moduledoc "ElevenLabs' implemented Vxpipe service capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "elevenlabs"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.APIKeyCredential,
      stt: Vxpipe.Providers.ElevenLabs.STTSession,
      tts: Vxpipe.Providers.ElevenLabs.TTSSession
    }
  end
end
