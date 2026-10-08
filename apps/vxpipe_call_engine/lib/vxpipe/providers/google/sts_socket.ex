defmodule Vxpipe.Providers.Google.STSSocket do
  @moduledoc false

  alias Vxpipe.CallEngine.Speech.Socket
  alias Vxpipe.Providers.Google.STS

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
    with {:ok, payload} <- STS.encode_audio(audio),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def send_text(socket, text) do
    with {:ok, payload} <- STS.encode_text(text),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def send_activity(socket, boundary) do
    with {:ok, payload} <- STS.encode_activity(boundary),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def send_tool_result(socket, call_id, name, result) do
    with {:ok, payload} <- STS.encode_tool_result(call_id, name, result),
         do: Socket.send_frame(socket, {:text, payload})
  end

  def close(socket),
    do: Socket.close(socket, ~s({"realtimeInput":{"audioStreamEnd":true}}))

  def retire(socket), do: Socket.retire(socket)

  @impl true
  def handle_frame({:text, message}, state), do: forward(message, state)
  def handle_frame({:binary, message}, state), do: forward(message, state)

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end

  @impl true
  def handle_peer_close(status, reason, state) do
    classification =
      if status == 1_008 and
           String.ends_with?(reason, "session is already connected to an existing client"),
         do: :session_active,
         else: :connection_lost

    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, classification}})
    {:ok, state}
  end

  defp forward(message, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, message}})
    {:ok, state}
  end
end
