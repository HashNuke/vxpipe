defmodule Vxpipe.CallEngine.SpeechContextUnsupportedProbe do
  @moduledoc false
  # Deliberately advertises the descriptor without the optional atomic callback.
  alias Vxpipe.CallEngine.SpeechContextProbe, as: Probe
  defdelegate configure(options), to: Probe
  defdelegate start_link(options), to: Probe
  defdelegate push_audio(pid, pcm), to: Probe
  defdelegate push_text(pid, ref, text), to: Probe
  defdelegate input_activity(pid, boundary), to: Probe
  defdelegate interrupt(pid, ref), to: Probe
  defdelegate send_tool_result(pid, ref, result), to: Probe
  defdelegate close(pid), to: Probe
end
