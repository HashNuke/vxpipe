defmodule Vxpipe.CallEngine.TestGPTLiveTransport do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_control(socket, message), do: GenServer.call(socket, {:control, message})
  def close(socket), do: GenServer.call(socket, :close)
  def deliver(socket, message), do: GenServer.cast(socket, {:deliver, message})
  def deliver_sync(socket, message), do: GenServer.call(socket, {:deliver_sync, message})
  def deliver_raw(socket, payload), do: GenServer.cast(socket, {:deliver_raw, payload})
  def disconnect(socket), do: GenServer.cast(socket, :disconnect)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    owner = Keyword.fetch!(options, :owner)
    send(observer, {:test_gpt_live_started, self(), Keyword.fetch!(options, :connection)})
    {:ok, %{observer: observer, owner: owner}}
  end

  @impl true
  def handle_call({:control, message}, _from, state) do
    send(state.observer, {:test_gpt_live_control, self(), JSON.decode!(message)})
    {:reply, :ok, state}
  end

  def handle_call({:deliver_sync, message}, _from, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, JSON.encode!(message)}})
    {:reply, :ok, state}
  end

  def handle_call(:close, _from, state), do: {:stop, :normal, :ok, state}

  @impl true
  def handle_cast({:deliver, message}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, JSON.encode!(message)}})
    {:noreply, state}
  end

  def handle_cast({:deliver_raw, payload}, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:message, payload}})
    {:noreply, state}
  end

  def handle_cast(:disconnect, state) do
    send(state.owner, {:vxpipe_sts_transport, self(), {:closed, :connection_lost}})
    {:noreply, state}
  end
end
