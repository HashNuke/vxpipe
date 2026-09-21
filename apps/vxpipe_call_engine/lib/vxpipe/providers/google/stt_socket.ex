defmodule Vxpipe.Providers.Google.STTSocket do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.Google.STT

  @behaviour Socket

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)

    options =
      if Keyword.get(options, :deferred, false),
        do: Keyword.put(options, :connect_mode, :deferred),
        else: options

    Socket.start_link(options, __MODULE__, %{owner: owner})
  end

  def send_control(socket, payload), do: Socket.send_frame(socket, {:text, payload})

  def send_audio(socket, audio) do
    with {:ok, payload} <- STT.encode_audio(audio),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def close(socket),
    do: Socket.close(socket, ~s({"realtimeInput":{"audioStreamEnd":true}}))

  @impl true
  def handle_frame({:text, message}, state), do: forward(message, state)
  def handle_frame({:binary, message}, state), do: forward(message, state)

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end

  defp forward(message, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, message}})
    {:ok, state}
  end
end
