defmodule Vxpipe.Providers.MorseCodeApi.STTSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.MorseCodeApi.STT

  def start_link(options) do
    Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{
      owner: Keyword.fetch!(options, :owner),
      keepalive_interval: 10_000
    })
  end

  def send_audio(socket, audio) do
    with {:ok, payload} <- STT.encode_audio(audio),
         do: Socket.send_frame(socket, {:text, payload})
  end

  @impl true
  def keepalive_frame(_state), do: {:text, STT.keepalive()}

  @impl true
  def handle_frame({:text, payload}, state) do
    case STT.decode(payload) do
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
