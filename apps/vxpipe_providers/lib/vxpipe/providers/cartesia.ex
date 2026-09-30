defmodule Vxpipe.Providers.Cartesia do
  @moduledoc "Cartesia's implemented Vxpipe service capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "cartesia"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.APIKeyCredential,
      stt: Vxpipe.Providers.Cartesia.STTSession,
      tts: Vxpipe.Providers.Cartesia.TTSSession
    }
  end
end
