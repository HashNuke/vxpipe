defmodule Vxpipe.Gateway.TestWebRTCSourcePeer do
  @moduledoc false

  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def emit(peer, event), do: GenServer.call(peer, {:emit, event})
  def barrier_count(peer), do: GenServer.call(peer, :barrier_count)

  @impl true
  def init(options) do
    {:ok,
     %{
       owner: Keyword.fetch!(options, :owner),
       barrier_events: Keyword.get(options, :barrier_events, []),
       barrier_reply: Keyword.get(options, :barrier_reply, :ok),
       barriers: 0
     }}
  end

  @impl true
  def handle_call({:controlling_process, owner}, _from, state) do
    Enum.each(state.barrier_events, fn event -> send(owner, {:ex_webrtc, self(), event}) end)
    {:reply, state.barrier_reply, %{state | owner: owner, barriers: state.barriers + 1}}
  end

  def handle_call({:emit, event}, _from, state) do
    send(state.owner, {:ex_webrtc, self(), event})
    {:reply, :ok, state}
  end

  def handle_call(:barrier_count, _from, state), do: {:reply, state.barriers, state}
end
