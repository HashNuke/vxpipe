defmodule Vxpipe.Gateway.WebRTC.SourceReceiver do
  @moduledoc false

  use GenServer

  alias ExRTP.Packet

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :epoch)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    epoch = Keyword.fetch!(options, :epoch)
    clock = Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end)

    if is_pid(owner) and is_reference(epoch) and is_function(clock, 0) do
      {:ok, %{owner: owner, monitor: Process.monitor(owner), epoch: epoch, clock: clock}}
    else
      {:stop, :invalid_source_receiver}
    end
  end

  @impl true
  def handle_info({:ex_webrtc, _peer, {:rtp, _track, _rid, %Packet{}}} = message, state) do
    send(state.owner, {:vxpipe_webrtc_source, self(), state.epoch, state.clock.(), message})
    {:noreply, state}
  end

  def handle_info({:ex_webrtc, _peer, _event} = message, state) do
    send(state.owner, message)
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, monitor, :process, owner, _reason},
        %{monitor: monitor, owner: owner} = state
      ),
      do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}
end
