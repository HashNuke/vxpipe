defmodule Vxpipe.CallEngine.TestFailingSpeechToTextTransport do
  @moduledoc false

  @behaviour Vxpipe.CallEngine.Provider.SpeechToText.Transport

  @impl true
  def start_link(options) do
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    send(observer, :test_failing_stt_start_attempted)
    {:error, :simulated_start_failure}
  end

  @impl true
  def send_audio(_transport, _audio), do: {:error, :unavailable}

  @impl true
  def close(_transport), do: :ok
end
