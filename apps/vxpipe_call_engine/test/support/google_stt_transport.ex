defmodule Vxpipe.CallEngine.TestGoogleSTTTransport do
  @moduledoc false

  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_control(socket, message), do: GenServer.call(socket, {:control, message})
  def send_audio(socket, audio), do: GenServer.call(socket, {:audio, audio})
  def close(socket), do: GenServer.call(socket, :close)
  def deliver(socket, message), do: GenServer.cast(socket, {:deliver, message})
  def disconnect(socket), do: GenServer.cast(socket, :disconnect)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    owner = Keyword.fetch!(options, :owner)
    send(observer, {:test_google_stt_started, self(), Keyword.fetch!(options, :connection)})
    if Keyword.get(options, :deferred, false), do: send(owner, {:vxpipe_socket_connected, self()})

    ready_on_start =
      options |> Keyword.fetch!(:transport_options) |> Keyword.get(:ready_on_start, false)

    {:ok, %{observer: observer, owner: owner, ready_on_start: ready_on_start}}
  end

  @impl true
  def handle_call({:control, message}, _from, state) do
    send(state.observer, {:test_google_stt_control, self(), message})

    if state.ready_on_start,
      do: send(state.owner, {:vxpipe_stt_transport, self(), {:message, ~s({"setupComplete":{}})}})

    {:reply, :ok, state}
  end

  def handle_call({:audio, audio}, _from, state) do
    send(state.observer, {:test_google_stt_audio, self(), audio})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_cast({:deliver, message}, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, message}})
    {:noreply, state}
  end

  def handle_cast(:disconnect, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, :connection_lost}})
    {:noreply, state}
  end
end
