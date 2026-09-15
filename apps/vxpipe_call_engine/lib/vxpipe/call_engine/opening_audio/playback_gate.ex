defmodule Vxpipe.CallEngine.OpeningAudio.PlaybackGate do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.{AudioOutputFrame, OutputSink}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def release(gate), do: GenServer.call(gate, :release, 5_000)

  @impl true
  def init(options) do
    owner = Keyword.fetch!(options, :owner)
    sink = Keyword.fetch!(options, :output_sink)

    {:ok,
     %{
       owner: owner,
       sink: sink,
       connection_id: Keyword.fetch!(options, :connection_id),
       monitors: [Process.monitor(owner), Process.monitor(sink)],
       pending: nil,
       turn: nil,
       callback: nil,
       released?: false
     }}
  end

  @impl true
  def handle_call(
        {:vxpipe_audio_output, %AudioOutputFrame{connection_id: connection} = frame},
        from,
        %{connection_id: connection, pending: nil, released?: false} = state
      ) do
    send(state.owner, {:vxpipe_opening_audio_ready, self()})

    {:noreply,
     %{state | pending: {from, frame}, turn: frame.correlation_id, callback: frame.reply_to}}
  end

  def handle_call(:release, {owner, _tag}, %{owner: owner, pending: {from, frame}} = state) do
    result = OutputSink.push(state.sink, %{frame | audio_scope: :private, reply_to: self()})
    GenServer.reply(from, result)
    {:reply, result, %{state | pending: nil, released?: true}}
  end

  def handle_call(
        {:vxpipe_audio_output, %AudioOutputFrame{} = frame},
        _from,
        %{released?: true} = state
      )
      when frame.connection_id == state.connection_id and frame.correlation_id == state.turn and
             frame.reply_to == state.callback do
    {:reply, OutputSink.push(state.sink, %{frame | audio_scope: :private, reply_to: self()}),
     state}
  end

  def handle_call({:vxpipe_audio_output_finish, turn, callback}, _from, state)
      when state.released? and turn == state.turn and callback == state.callback do
    {:reply, OutputSink.finish(state.sink, turn, self()), state}
  end

  def handle_call({:vxpipe_audio_output_interrupt, turn, callback}, _from, state)
      when state.released? and turn == state.turn and callback == state.callback do
    {:reply, OutputSink.interrupt(state.sink, turn, self()), state}
  end

  def handle_call(_message, _from, state), do: {:reply, {:error, :unavailable}, state}

  @impl true
  def handle_info({:vxpipe_audio_playback, sink, turn, status}, state)
      when sink == state.sink and turn == state.turn and state.released? do
    send(state.callback, {:vxpipe_audio_playback, self(), turn, status})
    {:noreply, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    if monitor in state.monitors, do: {:stop, :normal, state}, else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
