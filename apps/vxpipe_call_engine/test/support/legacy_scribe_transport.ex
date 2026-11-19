defmodule Vxpipe.CallEngine.LegacyScribeTransport do
  @moduledoc false
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire
  defdelegate start_link(options), to: Wire
  defdelegate send_audio(pid, audio), to: Wire
  defdelegate observe(pid, handoff), to: Wire
  defdelegate commit(pid), to: Wire
end
