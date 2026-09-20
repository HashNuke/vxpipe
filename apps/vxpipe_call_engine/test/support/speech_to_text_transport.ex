defmodule Vxpipe.CallEngine.TestSpeechToTextTransport do
  @moduledoc false

  use GenServer

  def start_link(options) do
    options
    |> Keyword.fetch!(:transport_options)
    |> Keyword.get(:before_connect, fn -> :ok end)
    |> then(& &1.())

    GenServer.start_link(__MODULE__, options)
  end

  def send_audio(transport, audio), do: GenServer.call(transport, {:send_audio, audio})

  def close(transport), do: GenServer.call(transport, :close)

  def deliver(transport, payload), do: GenServer.cast(transport, {:deliver, payload})
  def disconnect(transport, reason), do: GenServer.cast(transport, {:disconnect, reason})
  def allow_audio(transport, result \\ :ok), do: GenServer.cast(transport, {:allow_audio, result})

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    transport_options = Keyword.fetch!(options, :transport_options)
    observer = Keyword.fetch!(transport_options, :observer)
    send(observer, {:test_stt_transport_started, self(), Keyword.fetch!(options, :connection)})

    if Keyword.get(transport_options, :ready_on_start, false) do
      send(
        owner,
        {:vxpipe_stt_transport, self(),
         {:message, ~s({"type":"Connected","request_id":"fixture-ready","sequence_id":0})}}
      )
    end

    {:ok,
     %{
       observer: observer,
       owner: owner,
       pending_audio: nil,
       before_close: Keyword.get(transport_options, :before_close, fn -> :ok end),
       send_mode: Keyword.get(transport_options, :send_mode, :immediate)
     }}
  end

  @impl true
  def handle_call({:send_audio, audio}, from, %{send_mode: :manual, pending_audio: nil} = state) do
    send(state.observer, {:test_stt_audio, self(), audio})
    {:noreply, %{state | pending_audio: from}}
  end

  def handle_call({:send_audio, audio}, _from, state) do
    send(state.observer, {:test_stt_audio, self(), audio})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state) do
    :ok = state.before_close.()
    send(state.observer, {:test_stt_transport_closed, self()})
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:deliver, payload}, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, payload}})
    {:noreply, state}
  end

  def handle_cast({:disconnect, reason}, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, reason}})
    {:noreply, state}
  end

  def handle_cast({:allow_audio, result}, %{pending_audio: from} = state) when from != nil do
    GenServer.reply(from, result)
    {:noreply, %{state | pending_audio: nil}}
  end
end
