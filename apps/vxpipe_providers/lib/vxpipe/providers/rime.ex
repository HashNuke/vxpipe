defmodule Vxpipe.Providers.Rime do
  @moduledoc "Rime's declared Vxpipe capabilities."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "rime"

  @impl true
  def capabilities do
    %{
      credential: Vxpipe.Providers.Rime.Credential,
      credential_validation: Vxpipe.Providers.Rime.CredentialValidation,
      tts: Vxpipe.Providers.Rime.TTSSession
    }
  end
end
