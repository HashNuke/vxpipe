defmodule Vxpipe.Console.Test.PCMOutput do
  @moduledoc "Controlled PCM recipient for configured-service acceptance; playback is acknowledged by the test."
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def complete(sink), do: GenServer.call(sink, :complete)
  def block(sink), do: GenServer.call(sink, :block)

  @impl true
  def init(options) do
    {:ok,
     %{
       observer: Keyword.fetch!(options, :observer),
       callback: nil,
       bytes: 0,
       rate: 16_000,
       blocked?: false,
       pending: nil
     }}
  end

  @impl true
  def handle_call(:block, _from, state), do: {:reply, :ok, %{state | blocked?: true}}

  def handle_call({:vxpipe_audio_output, frame}, from, state) do
    send(state.observer, {:configured_pcm, self(), frame})

    state = %{
      state
      | callback: {frame.reply_to, frame.correlation_id},
        bytes: state.bytes + byte_size(frame.payload),
        rate: frame.sample_rate
    }

    if state.blocked?, do: {:noreply, %{state | pending: from}}, else: {:reply, :ok, state}
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, _from, state) do
    send(state.observer, {:configured_pcm_finished, self(), turn})
    {:reply, :ok, %{state | callback: {callback, turn}}}
  end

  def handle_call(:complete, _from, %{callback: {callback, turn}} = state) do
    send(
      callback,
      {:vxpipe_audio_playback, self(), turn,
       {:completed, div(state.bytes * 1_000, state.rate * 2)}}
    )

    {:reply, :ok, %{state | callback: nil, bytes: 0}}
  end

  def handle_call(
        {:vxpipe_audio_output_interrupt, turn, callback},
        _from,
        %{callback: {callback, turn}} = state
      ) do
    if state.pending, do: GenServer.reply(state.pending, {:error, :interrupted})
    send(state.observer, {:configured_pcm_interrupted, self(), turn})
    {:reply, {:ok, 0}, %{state | callback: nil, bytes: 0, blocked?: false, pending: nil}}
  end

  def handle_call({:vxpipe_audio_output_interrupt, _turn, _callback}, _from, state),
    do: {:reply, {:error, :wrong_turn}, state}

  def handle_call(:vxpipe_audio_output_clear, _from, state),
    do: {:reply, {:ok, 0}, %{state | callback: nil, bytes: 0}}

  def handle_call(:vxpipe_audio_output_drain, _from, state), do: {:reply, :ok, state}

  def handle_call({:vxpipe_audio_output_hold, _generation}, _from, state),
    do: {:reply, :ok, state}

  def handle_call({:vxpipe_audio_output_release, _generation}, _from, state),
    do: {:reply, :ok, state}
end
