defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxSocket do
  @moduledoc false

  use WebSockex

  @behaviour Vxpipe.CallEngine.Provider.SpeechToText.Transport

  @default_connect_timeout 10_000
  @default_receive_timeout 60_000
  @send_timeout 5_000

  @impl Vxpipe.CallEngine.Provider.SpeechToText.Transport
  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    connection = Keyword.fetch!(options, :connection)
    transport_options = Keyword.fetch!(options, :transport_options)

    WebSockex.start_link(
      connection.url,
      __MODULE__,
      %{owner: owner},
      extra_headers: connection.headers,
      socket_connect_timeout:
        Keyword.get(transport_options, :connect_timeout, @default_connect_timeout),
      socket_recv_timeout:
        Keyword.get(transport_options, :receive_timeout, @default_receive_timeout)
    )
  end

  @impl Vxpipe.CallEngine.Provider.SpeechToText.Transport
  def send_audio(socket, audio) when is_binary(audio) do
    WebSockex.send_frame(socket, {:binary, audio}, @send_timeout)
  end

  @impl Vxpipe.CallEngine.Provider.SpeechToText.Transport
  def close(socket) do
    result = WebSockex.send_frame(socket, {:text, JSON.encode!(%{"type" => "CloseStream"})})
    :ok = WebSockex.cast(socket, :close)
    result
  end

  @impl true
  def handle_frame({:text, message}, state), do: forward_message(message, state)

  def handle_frame({:binary, message}, state), do: forward_message(message, state)

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end

  @impl true
  def handle_cast(:close, state), do: {:close, state}

  defp forward_message(message, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, message}})
    {:ok, state}
  end
end
