defmodule Vxpipe.CallEngine.CallLoad.Sink do
  @moduledoc "Clock-paced, bounded local PCM consumer for comparative call loads."
  use GenServer

  alias Vxpipe.CallEngine.CallLoad.Playback
  alias Vxpipe.CallEngine.Provider.MorseCode.{Config, Decoder}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)
  def stats(pid), do: GenServer.call(pid, :stats)

  @impl true
  def init(options) do
    {:ok, config} = Config.new(unit_duration_ms: 20)

    {:ok,
     %{
       observer: Keyword.fetch!(options, :observer),
       config: config,
       active: nil,
       stats: %{
         received_chunks: 0,
         rejected_chunks: 0,
         interrupted_chunks: 0,
         cleared_chunks: 0,
         decoded_replies: 0,
         incorrect_replies: 0,
         completed_playbacks: 0
       }
     }}
  end

  @impl true
  def handle_call(:stats, _from, state), do: {:reply, state.stats, state}

  def handle_call({:vxpipe_audio_output, frame}, _from, state) do
    now = now()
    active = state.active || new_turn(frame, state.config, now)

    with true <- frame.codec == :linear16 and frame.sample_rate == 16_000 and frame.channels == 1,
         true <- active.turn == frame.correlation_id,
         {:ok, ledger} <-
           Playback.accept(active.ledger, byte_size(frame.payload), frame.sample_rate, now),
         {:ok, decoder, events} <- Decoder.push(active.decoder, frame.payload) do
      if state.active == nil do
        notify(state, {:first_audio, frame.correlation_id, now})
        send(frame.reply_to, {:vxpipe_audio_playback, self(), frame.correlation_id, :started})
      end

      decoded = Enum.count(events, &match?({:final, _}, &1))

      incorrect =
        Enum.count(events, fn
          {:final, text} -> text != "RECEIVED HI"
          _ -> false
        end)

      active = %{
        active
        | ledger: ledger,
          decoder: decoder,
          chunks: [ledger.total_ms | active.chunks]
      }

      state = %{state | active: active}
      state = update_in(state.stats.received_chunks, &(&1 + 1))
      state = update_in(state.stats.decoded_replies, &(&1 + decoded))
      state = update_in(state.stats.incorrect_replies, &(&1 + incorrect))
      {:reply, :ok, state}
    else
      _ ->
        {:reply, {:error, :output_bound_or_format},
         update_in(state.stats.rejected_chunks, &(&1 + 1))}
    end
  end

  def handle_call(
        {:vxpipe_audio_output_finish, turn, callback},
        _from,
        %{active: %{turn: turn}} = state
      ) do
    delay = max(0, ceil(state.active.ledger.due - now()))
    Process.send_after(self(), {:finish, state.active.token}, delay)
    {:reply, :ok, put_in(state.active.callback, callback)}
  end

  def handle_call(
        {:vxpipe_audio_output_interrupt, turn, _callback},
        _from,
        %{active: %{turn: turn}} = state
      ) do
    played = Playback.played_ms(state.active.ledger, now())
    dropped = Enum.count(state.active.chunks, &(&1 > played))
    notify(state, {:sink_interrupted, turn, now()})
    state = update_in(state.stats.interrupted_chunks, &(&1 + dropped))
    {:reply, {:ok, played}, %{state | active: nil}}
  end

  def handle_call({:vxpipe_audio_output_interrupt, _, _}, _from, state),
    do: {:reply, {:error, :wrong_turn}, state}

  def handle_call(:vxpipe_audio_output_clear, _from, %{active: nil} = state),
    do: {:reply, {:ok, 0}, state}

  def handle_call(:vxpipe_audio_output_clear, _from, state) do
    played = Playback.played_ms(state.active.ledger, now())
    dropped = Enum.count(state.active.chunks, &(&1 > played))
    state = update_in(state.stats.cleared_chunks, &(&1 + dropped))
    {:reply, {:ok, played}, %{state | active: nil}}
  end

  def handle_call(:vxpipe_audio_output_drain, _from, state), do: {:reply, :ok, state}
  def handle_call({:vxpipe_audio_output_hold, _}, _from, state), do: {:reply, :ok, state}
  def handle_call({:vxpipe_audio_output_release, _}, _from, state), do: {:reply, :ok, state}
  def handle_call({:vxpipe_bind_recording_egress, _}, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info({:finish, token}, %{active: %{token: token} = active} = state) do
    played = Playback.played_ms(active.ledger, now())
    send(active.callback, {:vxpipe_audio_playback, self(), active.turn, {:completed, played}})
    notify(state, {:playback_ack, active.turn, now()})
    state = update_in(state.stats.completed_playbacks, &(&1 + 1))
    {:noreply, %{state | active: nil}}
  end

  def handle_info({:finish, _old}, state), do: {:noreply, state}

  defp new_turn(frame, config, now) do
    {:ok, decoder} = Decoder.new(config)

    %{
      turn: frame.correlation_id,
      callback: frame.reply_to,
      ledger: Playback.new(now),
      decoder: decoder,
      chunks: [],
      token: make_ref()
    }
  end

  defp notify(state, event), do: send(state.observer, {:call_load, event})
  defp now, do: System.monotonic_time(:millisecond)
end
