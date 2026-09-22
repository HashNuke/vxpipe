defmodule Vxpipe.CallEngine.TestSpeechSocketCloseProbe do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.Socket

  def start_link(options) do
    Socket.start_link(options, __MODULE__, %{owner: Keyword.fetch!(options, :owner)})
  end

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}
  end

  @impl true
  def handle_frame({:binary, data}, state) do
    reference = make_ref()
    notify(state, {:awaiting, reference, data})
    {:await, reference, state}
  end

  def handle_frame(frame, state), do: notify(state, {:frame, frame})

  @impl true
  def handle_disconnect(reason, state), do: notify(state, {:disconnect, reason})

  @impl true
  def handle_peer_close(status, state), do: notify(state, {:peer_close, status})

  defp notify(state, event) do
    send(state.owner, {:socket_close_probe, self(), event})
    {:ok, state}
  end
end
