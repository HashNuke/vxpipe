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
  def init(options), do: {:ok, %{callback: nil, observer: Keyword.fetch!(options, :observer)}}

  @impl true
  def handle_call({:vxpipe_audio_output, frame}, _from, state) do
    send(state.observer, {:test_audio_output, self(), frame})
    {:reply, :ok, state}
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
    send(callback, {:vxpipe_audio_playback, self(), turn, :completed})
    {:reply, :ok, %{state | callback: nil}}
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

    {:reply, :ok, state}
  end
end
