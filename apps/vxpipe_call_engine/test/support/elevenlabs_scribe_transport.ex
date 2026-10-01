defmodule Vxpipe.CallEngine.TestElevenLabsScribeTransport do
  @moduledoc false
  use GenServer
  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)
  def commit(pid), do: GenServer.call(pid, :commit, 5_000)
  def deliver(pid, event), do: GenServer.call(pid, {:deliver, event}, 5_000)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    send(observer, {:scribe_started, self()})
    {:ok, %{owner: Keyword.fetch!(options, :owner), observer: observer}}
  end

  @impl true
  def handle_call({:audio, audio}, _from, state) do
    send(state.observer, {:scribe_audio, self(), audio})
    {:reply, :ok, state}
  end

  def handle_call(:commit, _from, state) do
    send(state.observer, {:scribe_commit, self()})
    {:reply, :ok, state}
  end

  def handle_call({:deliver, event}, _from, state) do
    send(state.owner, {:vxpipe_scribe_transport, self(), {:event, event}})
    {:reply, :ok, state}
  end
end
