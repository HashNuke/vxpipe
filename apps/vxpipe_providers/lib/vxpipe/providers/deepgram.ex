defmodule Vxpipe.Providers.Deepgram do
  @moduledoc "Deepgram's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "deepgram"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Deepgram.Credential,
      credential_validation: Vxpipe.Providers.Deepgram.CredentialValidation,
      stt: Vxpipe.Providers.Deepgram.STTSession,
      tts: Vxpipe.Providers.Deepgram.TTSSession
    }
  end
end
