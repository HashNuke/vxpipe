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
       callback: nil,
       observer: Keyword.fetch!(options, :observer),
       pending_output: nil,
       played_ms: 0
     }}
  end

  @impl true
  def handle_call({:vxpipe_audio_output, frame}, from, state) do
    send(state.observer, {:test_audio_output, self(), frame})
    state = %{state | callback: {frame.reply_to, frame.correlation_id}}

    if state.block_output do
      {:noreply, %{state | pending_output: from}}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, _from, state) do
    send(state.observer, {:test_audio_output_finish, self(), turn})
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
