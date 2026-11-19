defmodule Vxpipe.CallEngine.TestElevenLabsScribeTransport do
  @moduledoc false
  use GenServer
  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)
  def observe(pid, handoff), do: send(pid, {:observe, self(), handoff})
  def commit(pid), do: GenServer.call(pid, :commit, 5_000)
  def deliver_frame(pid, payload), do: GenServer.call(pid, {:frame, payload})
  def deliver(pid, event), do: GenServer.call(pid, {:deliver, event}, 5_000)

  @impl true
  def init(options) do
    observer = options |> Keyword.fetch!(:transport_options) |> Keyword.fetch!(:observer)
    send(observer, {:scribe_started, self()})

    {:ok,
     %{
       owner: Keyword.fetch!(options, :owner),
       observer: observer,
       audio_count: 0,
       fail_audio_at: Keyword.get(Keyword.fetch!(options, :transport_options), :fail_audio_at),
       diagnostic_handoff: Keyword.get(options, :diagnostic_handoff),
       model: Keyword.get(options, :model, "scribe_v2_realtime"),
       commit_strategy: Keyword.get(options, :commit_strategy, :manual)
     }}
  end

  @impl true
  def handle_call({:audio, audio}, _from, state) do
    send(state.observer, {:scribe_audio, self(), audio})
    count = state.audio_count + 1
    result = if count == state.fail_audio_at, do: {:error, :transport_failed}, else: :ok
    {:reply, result, %{state | audio_count: count}}
  end

  def handle_call(:commit, _from, state) do
    send(state.observer, {:scribe_commit, self()})
    {:reply, :ok, state}
  end

  def handle_call({:frame, payload}, _from, state) do
    {:ok, next} = Vxpipe.Providers.ElevenLabs.ScribeSocket.handle_frame({:text, payload}, state)
    {:reply, :ok, next}
  end

  def handle_call({:deliver, event}, _from, state) do
    send(state.owner, {:vxpipe_scribe_transport, self(), {:event, event}})
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:observe, owner, handoff}, %{owner: owner} = state) do
    send(state.observer, {:scribe_observing, self(), handoff.token})
    {:noreply, %{state | diagnostic_handoff: handoff}}
  end
end
