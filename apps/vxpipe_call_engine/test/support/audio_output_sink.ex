defmodule Vxpipe.CallEngine.TestAudioOutputSink do
  @moduledoc false

  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def playback_started(sink), do: GenServer.call(sink, :playback_started)

  def playback_progress(sink, played_ms, total_ms) do
    GenServer.call(sink, {:playback_progress, played_ms, total_ms})
  end

  def playback_completed(sink), do: GenServer.call(sink, :playback_completed)

  @impl true
  def init(options) do
    {:ok,
     %{
       block_output: Keyword.get(options, :block_output, false),
       defer_drain: Keyword.get(options, :defer_drain, false),
       pending_drain: nil,
       defer_release: false,
       pending_release: nil,
       callback: nil,
       observer: Keyword.fetch!(options, :observer),
       pending_output: nil,
       played_ms: 0,
       automatic_playback_ms: nil,
       output_generation: 0,
       recording_egress: nil
     }}
  end

  @impl true
  def handle_call({:vxpipe_audio_output_hold, generation}, _from, state),
    do: {:reply, :ok, %{state | output_generation: generation}}

  def handle_call(
        {:vxpipe_audio_output_release, generation},
        from,
        %{output_generation: generation} = state
      ) do
    state = %{state | output_generation: 0}

    if state.defer_release do
      send(state.observer, {:test_audio_output_released, self()})
      {:noreply, %{state | pending_release: from}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:defer_release, deferred?}, _from, state) when is_boolean(deferred?),
    do: {:reply, :ok, %{state | defer_release: deferred?}}

  def handle_call({:complete_release, result}, _from, state) do
    GenServer.reply(state.pending_release, result)
    {:reply, :ok, %{state | pending_release: nil, defer_release: false}}
  end

  def handle_call(:vxpipe_audio_output_clear, _from, state),
    do: {:reply, {:ok, 0}, %{state | callback: nil}}

  def handle_call({:vxpipe_bind_recording_egress, handoff}, _from, state) do
    send(state.observer, {:test_audio_recording_bound, self(), handoff})
    {:reply, :ok, %{state | recording_egress: handoff}}
  end

  def handle_call(:vxpipe_audio_output_drain, from, state) do
    send(state.observer, {:test_audio_output_drain, self()})

    if state.defer_drain,
      do: {:noreply, %{state | pending_drain: from}},
      else: {:reply, :ok, state}
  end

  def handle_call(:complete_drain, _from, state) do
    GenServer.reply(state.pending_drain, :ok)
    {:reply, :ok, %{state | pending_drain: nil}}
  end

  def handle_call({:defer_drain, deferred?}, _from, state) when is_boolean(deferred?),
    do: {:reply, :ok, %{state | defer_drain: deferred?}}

  def handle_call({:block_output, blocked?}, _from, %{pending_output: nil} = state)
      when is_boolean(blocked?),
      do: {:reply, :ok, %{state | block_output: blocked?}}

  def handle_call({:vxpipe_audio_output, frame}, from, state) do
    send(state.observer, {:test_audio_output, self(), frame})

    automatic =
      if frame.audio_scope == :private and frame.output_generation > 0,
        do: div(byte_size(frame.payload) * 1_000, frame.sample_rate * frame.channels * 2)

    state = %{
      state
      | callback: {frame.reply_to, frame.correlation_id},
        automatic_playback_ms: automatic
    }

    if state.block_output do
      {:noreply, %{state | pending_output: from}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, _from, state) do
    send(state.observer, {:test_audio_output_finish, self(), turn})

    if state.automatic_playback_ms do
      Process.send_after(
        callback,
        {:vxpipe_audio_playback, self(), turn, {:completed, state.automatic_playback_ms}},
        state.automatic_playback_ms
      )
    end

    {:reply, :ok, %{state | callback: {callback, turn}}}
  end

  def handle_call(:playback_started, _from, %{callback: {callback, turn}} = state) do
    send(callback, {:vxpipe_audio_playback, self(), turn, :started})
    {:reply, :ok, state}
  end

  def handle_call(:playback_completed, _from, %{callback: {callback, turn}} = state) do
    send(callback, {:vxpipe_audio_playback, self(), turn, {:completed, state.played_ms}})
    {:reply, :ok, %{state | callback: nil, played_ms: 0}}
  end

  def handle_call(
        {:playback_progress, played_ms, total_ms},
        _from,
        %{callback: {callback, turn}} = state
      ) do
    send(
      callback,
      {:vxpipe_audio_playback, self(), turn, {:progress, played_ms, total_ms}}
    )

    {:reply, :ok, %{state | played_ms: played_ms}}
  end

  def handle_call(
        {:vxpipe_audio_output_interrupt, turn, callback},
        _from,
        %{callback: {callback, turn}} = state
      ) do
    send(state.observer, {:test_audio_output_interrupt, self(), turn, state.played_ms})

    if state.pending_output != nil do
      GenServer.reply(state.pending_output, {:error, :interrupted})
    end

    {:reply, {:ok, state.played_ms}, %{state | callback: nil, pending_output: nil, played_ms: 0}}
  end

  def handle_call({:vxpipe_audio_output_interrupt, _turn, _callback}, _from, state) do
    {:reply, {:error, :wrong_turn}, state}
  end
end
