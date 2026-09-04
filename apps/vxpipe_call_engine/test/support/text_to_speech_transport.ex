defmodule Vxpipe.CallEngine.TestTextToSpeechTransport do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Provider.TextToSpeech.Transport

  @impl true
  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def send_control(transport, payload), do: GenServer.call(transport, {:send_control, payload})

  @impl true
  def close(transport), do: GenServer.call(transport, :close)

  def deliver_control(transport, payload), do: GenServer.cast(transport, {:control, payload})
  def deliver_audio(transport, payload), do: GenServer.cast(transport, {:audio, payload})
  def disconnect(transport, reason), do: GenServer.cast(transport, {:disconnect, reason})

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    send(observer, {:test_tts_transport_started, self(), Keyword.fetch!(options, :connection)})
    {:ok, %{observer: observer, owner: owner}}
  end

  @impl true
  def handle_call({:send_control, payload}, _from, state) do
    send(state.observer, {:test_tts_control, self(), payload})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state) do
    send(state.observer, {:test_tts_transport_closed, self()})
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:control, payload}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:control, payload}})
    {:noreply, state}
  end

  def handle_cast({:audio, payload}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:audio, payload}})
    {:noreply, state}
  end

  def handle_cast({:disconnect, reason}, state) do
    send(state.owner, {:vxpipe_tts_transport, self(), {:closed, reason}})
    {:noreply, state}
  end
end
