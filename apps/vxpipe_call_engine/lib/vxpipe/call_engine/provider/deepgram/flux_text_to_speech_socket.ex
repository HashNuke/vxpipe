defmodule Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeechSocket do
  @moduledoc false

  use WebSockex

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport

  @default_connect_timeout 10_000
  @default_keepalive_interval 30_000
  @default_receive_timeout 60_000
  @output_timeout 5_000
  @send_timeout 5_000

  @impl true
  def start_link(options) do
    owner = Keyword.fetch!(options, :owner)
    connection = Keyword.fetch!(options, :connection)
    transport_options = Keyword.fetch!(options, :transport_options)

    WebSockex.start_link(
      connection.url,
      __MODULE__,
      %{
        keepalive_interval:
          Keyword.get(transport_options, :keepalive_interval, @default_keepalive_interval),
        owner: owner
      },
      extra_headers: connection.headers,
      socket_connect_timeout:
        Keyword.get(transport_options, :connect_timeout, @default_connect_timeout),
      socket_recv_timeout:
        Keyword.get(transport_options, :receive_timeout, @default_receive_timeout)
    )
  end

  @impl true
  def send_control(socket, payload) when is_binary(payload) do
    WebSockex.send_frame(socket, {:text, payload}, @send_timeout)
  end

  @impl true
  def close(socket) do
    result = send_control(socket, JSON.encode!(%{"type" => "Close"}))
    :ok = WebSockex.cast(socket, :close)
    result
  end

  @impl true
  def handle_connect(_connection, state) do
    schedule_keepalive(state.keepalive_interval)
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, message}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, message}})
    {:ok, state}
  end

  def handle_frame({:binary, audio}, state) do
    reference = make_ref()
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, reference, audio}})

    receive do
      {:vxpipe_tts_audio_result, owner, ^reference, :ok} when owner == state.owner ->
        {:ok, state}

      {:vxpipe_tts_audio_result, owner, ^reference, {:error, _reason}}
      when owner == state.owner ->
        {:close, state}
    after
      @output_timeout -> {:close, state}
    end
  end

  @impl true
  def handle_info(:keepalive, state) do
    schedule_keepalive(state.keepalive_interval)
    {:reply, {:ping, <<>>}, state}
  end

  @impl true
  def handle_disconnect(_disconnect, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, :connection_lost}})
    {:ok, state}
  end

  @impl true
  def handle_cast(:close, state), do: {:close, state}

  defp schedule_keepalive(interval) do
    _timer = Process.send_after(self(), :keepalive, interval)
    :ok
  end
end
