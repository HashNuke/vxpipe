defmodule Vxpipe.Providers.Cartesia.STTSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.Cartesia.STT

  def start_link(options) do
    Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{
      owner: Keyword.fetch!(options, :owner)
    })
  end

  def send_audio(socket, audio) do
    with :ok <- STT.validate_audio(audio), do: Socket.send_frame(socket, {:binary, audio})
  end

  def finish_input(socket), do: Socket.send_frame(socket, {:text, ~s({"type":"close"})})

  @impl true
  def handle_frame({:text, payload}, state), do: notify(state, {:message, payload})
  def handle_frame(_invalid, state), do: notify(state, {:closed, :invalid_frame})

  @impl true
  def handle_disconnect(_reason, state), do: notify(state, {:closed, :connection_lost})

  @impl true
  def handle_peer_close(status, state), do: notify(state, {:peer_closed, status})

  defp notify(state, event) do
    send(state.owner, {:vxpipe_stt_transport, self(), event})
    {:ok, state}
  end
end
