defmodule Vxpipe.CallEngine.LiveContextTTSSocket do
  @moduledoc false
  alias Vxpipe.CallEngine.Speech.ContextTTSSocket

  def start_link(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)

    with {:ok, socket} <- ContextTTSSocket.start_link(options) do
      send(observer, {:live_tts_socket, socket})
      {:ok, socket}
    end
  end

  defdelegate send_control(socket, payload), to: ContextTTSSocket
  defdelegate close(socket, goodbye), to: ContextTTSSocket
end
