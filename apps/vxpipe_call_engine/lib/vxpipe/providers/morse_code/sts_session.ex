defmodule Vxpipe.Providers.MorseCode.STSSession do
  @moduledoc "Credential-free local Morse STS under the MorseCode provider namespace."

  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeSTS.Session, as: Native

  @impl true
  defdelegate configure(options), to: Native

  @impl true
  defdelegate start_link(options), to: Native

  @impl true
  defdelegate push_audio(pid, audio), to: Native

  @impl true
  defdelegate push_text(pid, reference, text), to: Native

  @impl true
  defdelegate input_activity(pid, boundary), to: Native

  @impl true
  defdelegate interrupt(pid, turn_ref), to: Native

  @impl true
  defdelegate send_tool_result(pid, call_ref, result), to: Native

  @impl true
  defdelegate close(pid), to: Native
end
