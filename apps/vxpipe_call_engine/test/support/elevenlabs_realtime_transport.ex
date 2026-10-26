defmodule Vxpipe.CallEngine.TestElevenLabsRealtimeTransport do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_control(pid, message), do: GenServer.call(pid, {:send, message})
  def deliver(pid, message), do: GenServer.call(pid, {:deliver, message})
  def close(pid), do: GenServer.stop(pid, :normal)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    owner = Keyword.fetch!(options, :owner)
    send(observer, {:realtime_wire, self()})
    send(owner, {:vxpipe_socket_connected, self()})
    {:ok, %{observer: observer, owner: owner}}
  end

  @impl true
  def handle_call({:send, message}, _from, state) do
    send(state.observer, {:realtime_sent, self(), message})
    {:reply, :ok, state}
  end

  def handle_call({:deliver, message}, _from, state) do
    send(state.owner, {:elevenlabs_realtime, self(), JSON.encode!(message)})
    {:reply, :ok, state}
  end
end
