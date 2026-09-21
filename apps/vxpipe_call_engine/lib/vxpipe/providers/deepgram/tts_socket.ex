defmodule Vxpipe.Providers.Deepgram.TTSSocket do
  @moduledoc false

  alias Vxpipe.Providers.Deepgram.Socket

  @behaviour Socket

  @default_keepalive_interval 30_000

  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    transport_options = Keyword.fetch!(options, :transport_options)

    Socket.start_link(
      options,
      __MODULE__,
      %{
        keepalive_interval:
          Keyword.get(transport_options, :keepalive_interval, @default_keepalive_interval),
        owner: owner
      }
    )
  end

  def send_control(socket, payload) when is_binary(payload) do
    Socket.send_frame(socket, {:text, payload})
  end

  def close(socket) do
    Socket.close(socket, JSON.encode!(%{"type" => "Close"}))
  end

  @impl true
  def handle_frame({:text, message}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, message}})
    {:ok, state}
  end

  def handle_frame({:binary, audio}, state) do
    reference = make_ref()
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, audio}})

    {:await, reference, state}
  end

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end
end
