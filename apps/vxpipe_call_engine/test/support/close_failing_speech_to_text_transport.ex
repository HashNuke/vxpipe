defmodule Vxpipe.CallEngine.TestCloseFailingSpeechToTextTransport do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.SpeechToText.Transport

  alias Vxpipe.CallEngine.TestSpeechToTextTransport

  @impl true
  defdelegate start_link(options), to: TestSpeechToTextTransport

  @impl true
  defdelegate send_audio(transport, audio), to: TestSpeechToTextTransport

  @impl true
  def close(_transport), do: exit(:simulated_close_failure)
end
