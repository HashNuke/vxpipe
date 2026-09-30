defmodule Vxpipe.Providers.ElevenLabs.ScribeSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.ElevenLabs.Scribe

  def start_link(options) do
    Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{
      owner: Keyword.fetch!(options, :owner)
    })
  end

  def send_audio(socket, audio) do
    with {:ok, payload} <- Scribe.encode_audio(audio),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def commit(socket), do: Socket.send_frame(socket, {:text, Scribe.commit()})

  @impl true
  def handle_frame({:text, payload}, state) do
    case Scribe.decode(payload) do
      {:ok, event} -> notify(state, {:event, event})
      {:error, reason} -> notify(state, {:closed, reason})
    end
  end

  def handle_frame(_invalid, state), do: notify(state, {:closed, :invalid_frame})

  @impl true
  def handle_disconnect(_reason, state), do: notify(state, {:closed, :connection_lost})

  @impl true
  def handle_peer_close(status, state), do: notify(state, {:peer_closed, status})

  defp notify(state, event) do
    send(state.owner, {:vxpipe_scribe_transport, self(), event})
    {:ok, state}
  end
end
