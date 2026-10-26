defmodule Vxpipe.Providers.ElevenLabs.RealtimeSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.Socket

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    Socket.start_link(Keyword.put(options, :connect_mode, :deferred), __MODULE__, %{owner: owner})
  end

  def send_control(socket, message), do: Socket.send_frame(socket, {:text, JSON.encode!(message)})
  def close(socket), do: GenServer.stop(socket, :normal, 1_000)

  def ack(socket, reference) do
    send(socket, {:vxpipe_tts_audio_result, self(), reference, :ok})
    :ok
  end

  @impl true
  def handle_frame({kind, payload}, state) when kind in [:text, :binary] do
    reference = make_ref()
    send(state.owner, {:elevenlabs_realtime, self(), reference, payload})
    {:await, reference, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.owner, {:elevenlabs_realtime_closed, self()})
    {:ok, state}
  end
end
