defmodule Vxpipe.CallEngine.TestFailingTextToSpeechTransport do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport

  @impl true
  def start_link(options) do
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    send(observer, {:test_failing_tts_start_attempted, Keyword.fetch!(options, :connection)})
    {:error, :simulated_start_failure}
  end

  @impl true
  def send_control(_transport, _payload), do: {:error, :unavailable}

  @impl true
  def close(_transport), do: :ok
end
