defmodule Vxpipe.Console.Test.StructuredBrowserTTSWire do
  @moduledoc "Observes synthetic acceptance text while delegating real Deepgram transport."

  alias Vxpipe.Providers.Deepgram.TTSSocket

  def start_link(options), do: TTSSocket.start_link(options)
  def close(socket), do: TTSSocket.close(socket)

  def send_control(socket, payload) do
    observer = Application.fetch_env!(:vxpipe_console, :structured_browser_observer)
    send(observer, {:structured_browser_tts, JSON.decode!(payload)})
    TTSSocket.send_control(socket, payload)
  end
end
