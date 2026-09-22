defmodule Vxpipe.Providers.MorseCode.STTSession do
  @moduledoc "Credential-free local Morse STT under the MorseCode provider namespace."

  @behaviour Vxpipe.CallEngine.Speech.STTProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTT.Session, as: Native

  @impl true
  defdelegate configure(options), to: Native

  @impl true
  defdelegate start_link(options), to: Native

  @impl true
  defdelegate push_audio(pid, audio), to: Native

  @impl true
  defdelegate finish_input(pid), to: Native

  @impl true
  defdelegate close(pid), to: Native
end
