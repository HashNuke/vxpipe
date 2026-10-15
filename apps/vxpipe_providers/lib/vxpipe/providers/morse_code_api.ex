defmodule Vxpipe.Providers.MorseCodeApi do
  @moduledoc "Implemented remote Morse speech capabilities. Keys provide protocol compatibility only."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "morse_code_api"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.MorseCodeApi.Credential,
      credential_validation: Vxpipe.Providers.MorseCodeApi.CredentialValidation,
      tts: Vxpipe.Providers.MorseCodeApi.TTSSession
    }
  end
end
