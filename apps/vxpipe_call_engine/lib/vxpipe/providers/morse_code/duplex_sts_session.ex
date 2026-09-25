defmodule Vxpipe.Providers.MorseCode.DuplexSTSSession do
  @moduledoc """
  Credential-free local Morse duplex STS under the MorseCode provider namespace.

  Declares the GPT-Live duplex descriptor facts and shares the provider-neutral
  `Speech.Duplex.TurnInference` and `Speech.Duplex.OutputSegmenter` modules.
  """

  @behaviour Vxpipe.CallEngine.Speech.STSProvider

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Session, as: Native

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
  defdelegate input_quiescent?(pid), to: Native

  @impl true
  defdelegate interrupt(pid, turn_ref), to: Native

  @impl true
  defdelegate send_tool_result(pid, call_ref, result), to: Native

  @impl true
  defdelegate close(pid), to: Native

  @doc "Emit the next `ms` of clock-paced output. The adapter owns the clock."
  defdelegate advance(pid, ms), to: Native
end
