defmodule Vxpipe.CallEngine.TestCartesiaSTTTransport do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(pid, audio), do: GenServer.call(pid, {:audio, audio})
  def finish_input(pid), do: GenServer.call(pid, :finish_input)
  def deliver(pid, event), do: GenServer.call(pid, {:deliver, event})
  def peer_close(pid, status), do: GenServer.call(pid, {:peer_close, status})
  def disconnect(pid), do: GenServer.call(pid, :disconnect)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    send(observer, {:cartesia_stt_started, self(), Keyword.fetch!(options, :connection)})
    {:ok, %{owner: Keyword.fetch!(options, :owner), observer: observer}}
  end

  @impl true
  def handle_call({:audio, audio}, _from, state) do
    send(state.observer, {:cartesia_stt_audio, self(), audio})
    {:reply, :ok, state}
  end

  def handle_call(:finish_input, _from, state) do
    send(state.observer, {:cartesia_stt_finish_input, self()})
    {:reply, :ok, state}
  end

  def handle_call({:deliver, event}, _from, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:message, JSON.encode!(event)}})
    {:reply, :ok, state}
  end

  def handle_call({:peer_close, status}, _from, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:peer_closed, status}})
    {:stop, :normal, :ok, state}
  end

  def handle_call(:disconnect, _from, state) do
    send(state.owner, {:vxpipe_stt_transport, self(), {:closed, :connection_lost}})
    {:stop, :normal, :ok, state}
  end
end
