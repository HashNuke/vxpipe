defmodule Vxpipe.CallEngine.TestFailingTextToSpeechTransport do
  @moduledoc false

  def start_link(options) do
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    send(observer, {:test_failing_tts_start_attempted, Keyword.fetch!(options, :connection)})
    Keyword.get(transport_options, :before_failure, fn -> :ok end).()
    {:error, :simulated_start_failure}
  end

  def send_control(_transport, _payload), do: {:error, :unavailable}

  def close(_transport), do: :ok
end
