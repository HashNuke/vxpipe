defmodule Vxpipe.CallEngine.LiveScribeSocket do
  @moduledoc false
  alias Vxpipe.Providers.ElevenLabs.ScribeSocket

  def start_link(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)

    with {:ok, socket} <- ScribeSocket.start_link(options) do
      send(observer, {:live_scribe_socket, socket})
      {:ok, socket}
    end
  end

  defdelegate send_audio(socket, audio), to: ScribeSocket
  defdelegate commit(socket), to: ScribeSocket
end
