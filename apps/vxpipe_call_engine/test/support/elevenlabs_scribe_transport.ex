defmodule Vxpipe.CallEngine.TestElevenLabsScribeTransport do
  @moduledoc false
  use GenServer
  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def send_audio(pid, audio), do: GenServer.call(pid, {:audio, audio}, 5_000)
  def observe(pid, handoff), do: send(pid, {:observe, self(), handoff})
  def commit_with_receipt(pid), do: GenServer.call(pid, :commit_with_receipt, 5_000)
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
       sent_samples: 0,
       timed_audio?:
         Keyword.get(Keyword.fetch!(options, :transport_options), :timed_audio, false),
       fail_audio_at: Keyword.get(Keyword.fetch!(options, :transport_options), :fail_audio_at),
       diagnostic_handoff: Keyword.get(options, :diagnostic_handoff),
       model: Keyword.get(options, :model, "scribe_v2_realtime"),
       commit_strategy: Keyword.get(options, :commit_strategy, :manual)
     }}
  end

  @impl true
  def handle_call({:audio, audio}, _from, state) do
    state =
      case Map.pop(state, :next_audio_event) do
        {nil, state} ->
          state

        {payload, state} ->
          {:ok, state} =
            Vxpipe.Providers.ElevenLabs.ScribeSocket.handle_frame({:text, payload}, state)

          state
      end

    message =
      if state.timed_audio?,
        do:
          {:scribe_audio, self(), state.audio_count, audio, System.monotonic_time(:microsecond)},
        else: {:scribe_audio, self(), audio}

    send(state.observer, message)
    count = state.audio_count + 1
    result = if count == state.fail_audio_at, do: {:error, :transport_failed}, else: :ok

    samples =
      if result == :ok,
        do: state.sent_samples + div(byte_size(audio), 2),
        else: state.sent_samples

    {:reply, result, %{state | audio_count: count, sent_samples: samples}}
  end

  def handle_call({:next_audio_event, payload}, _from, state),
    do: {:reply, :ok, Map.put(state, :next_audio_event, payload)}

  def handle_call({:commit_mode, mode}, _from, state),
    do: {:reply, :ok, Map.put(state, :commit_mode, mode)}

  def handle_call(:release_commit, _from, state) do
    {caller, stamp} = Map.fetch!(state, :held_commit)
    GenServer.reply(caller, {:ok, stamp})
    {:reply, :ok, Map.delete(state, :held_commit)}
  end

  def handle_call(:commit_with_receipt, from, state) do
    if Map.get(state, :commit_mode) == :fail do
      send(state.observer, {:scribe_commit_failed, self()})
      {:reply, {:error, :transport_failed}, state}
    else
      stamp = Vxpipe.CallEngine.Diagnostics.ProviderTiming.stamp(state.diagnostic_handoff)
      send(state.observer, {:scribe_commit, self()})
      send(state.observer, {:scribe_commit_receipt, self(), stamp})

      if Map.get(state, :commit_mode) == :hold,
        do: {:noreply, Map.put(state, :held_commit, {from, stamp})},
        else: {:reply, {:ok, stamp}, state}
    end
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
