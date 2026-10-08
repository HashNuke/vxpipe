defmodule Vxpipe.Providers.MorseCode.TTSSession do
  @moduledoc "Credential-free local Morse TTS under the MorseCode provider namespace."

  @behaviour Vxpipe.CallEngine.Speech.TTSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeTTS.Session, as: Native

  @impl true
  defdelegate models(), to: Native

  @impl true
  defdelegate configure(options), to: Native

  @impl true
  defdelegate start_link(options), to: Native

  @impl true
  defdelegate speak(pid, reference, text), to: Native

  @impl true
  defdelegate cancel(pid, reference, playback), to: Native

  @impl true
  defdelegate close(pid), to: Native
end
