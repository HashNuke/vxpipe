defmodule Vxpipe.Providers.Deepgram.STTSocket do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Socket

  @behaviour Socket

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    Socket.start_link(options, __MODULE__, %{owner: owner})
  end

  def send_audio(socket, audio) when is_binary(audio) do
    Socket.send_frame(socket, {:binary, audio})
  end

  def close(socket) do
    Socket.close(socket, JSON.encode!(%{"type" => "CloseStream"}))
  end

  @impl true
  def handle_frame({:text, message}, state), do: forward_message(message, state)

  def handle_frame({:binary, message}, state), do: forward_message(message, state)

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end

  defp forward_message(message, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, message}})
    {:ok, state}
  end
end
