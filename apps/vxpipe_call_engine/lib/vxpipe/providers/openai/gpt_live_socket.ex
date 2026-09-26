defmodule Vxpipe.Providers.OpenAI.GPTLiveSocket do
  @moduledoc false
  @behaviour Vxpipe.CallEngine.Speech.Socket

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.OpenAI.GPTLive

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    Socket.start_link(options, __MODULE__, %{owner: owner})
  end

  def send_control(socket, payload), do: Socket.send_frame(socket, {:text, payload})
  def close(socket), do: Socket.close(socket, JSON.encode!(GPTLive.close()))

  @impl true
  def handle_frame({:text, message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, message}})
    {:ok, state}
  end

  def handle_frame({:binary, _message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, :invalid_binary_frame}})
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end
end
