defmodule Vxpipe.CallEngine.Diagnostics.ReplayTransport do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(pid, _audio), do: GenServer.call(pid, :audio, 1_000)
  def commit(pid), do: GenServer.call(pid, :commit, 1_000)
  def tag_turn(pid, turn), do: GenServer.call(pid, {:tag_turn, turn}, 1_000)
  def deliver(pid, event), do: GenServer.call(pid, {:deliver, event}, 1_000)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    token = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:token)
    send(observer, {:diagnostic_replay_wire, token, self()})
    {:ok, %{owner: Keyword.fetch!(options, :owner), observer: observer, turn: nil}}
  end

  @impl true
  def handle_call(:audio, _from, state), do: {:reply, :ok, state}

  def handle_call(:commit, _from, state) do
    send(state.observer, {:diagnostic_replay_commit, self(), state.turn})
    {:reply, :ok, state}
  end

  def handle_call({:tag_turn, turn}, _from, state), do: {:reply, :ok, %{state | turn: turn}}

  def handle_call({:deliver, event}, _from, state) do
    send(state.owner, {:vxpipe_scribe_transport, self(), {:event, event}})
    {:reply, :ok, state}
  end
end
