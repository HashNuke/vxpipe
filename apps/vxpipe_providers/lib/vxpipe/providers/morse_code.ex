defmodule Vxpipe.Providers.MorseCode do
  @moduledoc "Credential-free local Morse proof provider (test configurations only)."
  @behaviour Vxpipe.Providers

  @impl true
  def id, do: "morse"

  @impl true
  def capabilities do
    %{
      stt: Vxpipe.Providers.MorseCode.STTSession,
      tts: Vxpipe.Providers.MorseCode.TTSSession,
      sts: Vxpipe.Providers.MorseCode.STSSession
    }
  end
end
