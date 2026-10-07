defmodule Vxpipe.CallEngine.WaitSounds.Player do
  @moduledoc """
  Independent bounded wait/cue playback.

  Each run streams the asset to every sink as one output turn. The player keeps at most a
  small window of frames ahead of real time, scheduled from the run's start rather than
  from each acknowledgement, so the sink always holds the next frames and a late timer never
  becomes a gap in the caller's audio. Pause and stop interrupt the sinks, whose reply gives
  the exact played duration; resume starts a new run from that frame. A finite cue finishes
  its turn once and completes after actual playback and a drain on every sink.
  """

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.OpeningAudio.Asset
  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.WaitSounds.Cursor

  # 48 kHz mono linear16: 96 bytes per millisecond, 20 ms per cursor frame.
  @bytes_per_ms 96
  @frame_ms 20
  # Frames the sink holds ahead of real time: absorbs scheduling delays without adding
  # noticeable latency to pause or stop, which interrupt the queued audio anyway.
  @window_frames 5
  @request_timeout_ms 5_000
  @interrupt_timeout_ms 1_000

  @fields [
    :owner,
    :episode_id,
    :tenant_id,
    :room_id,
    :incarnation_id,
    :participant_id,
    :connection_generation,
    :attempt_id,
    :phase,
    :sinks,
    :asset
  ]
  @derive {Inspect, only: [:episode_id, :phase, :mode, :offset]}
  defstruct @fields ++
              [
                loop: true,
                output_generation: 0,
                mode: :playing,
                offset: 0,
                cursor: 0,
                next_cursor: 0,
                sequence: 0,
                run: nil,
                pending: %{},
                monitors: %{},
                timer: nil,
                push_timer: nil,
                started_at: nil
              ]

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :episode_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def pause(player), do: GenServer.cast(player, :pause)
  def resume(player), do: GenServer.cast(player, :resume)
  def stop(player), do: GenServer.cast(player, :stop)

  def reconcile(player, scope, sinks),
    do: GenServer.call(player, {:reconcile, scope, sinks}, 1_000)

  @impl true
  def init(options) do
    state = struct!(__MODULE__, Keyword.take(options, @fields ++ [:loop, :output_generation]))

    case state.asset do
      %Asset{
        codec: :linear16,
        sample_rate: 48_000,
        channels: 1,
        byte_order: :little,
        payload: payload
      }
      when byte_size(payload) > 0 and rem(byte_size(payload), 2) == 0 ->
        if is_pid(state.owner) and map_size(state.sinks) > 0 and
             Enum.all?(state.sinks, fn {id, sink} -> is_binary(id) and is_pid(sink) end) do
          monitors =
            [state.owner | Map.values(state.sinks)] |> Map.new(&{Process.monitor(&1), &1})

          {:ok, %{state | monitors: monitors, started_at: Telemetry.started_at()},
           {:continue, :run}}
        else
          {:stop, :invalid_configuration}
        end

      _invalid ->
        {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_continue(:run, state), do: {:noreply, start_run(state)}

  @impl true
  def handle_call(
        {:reconcile, %{attempt_id: attempt, generation: generation}, sinks},
        _from,
        %{attempt_id: attempt, connection_generation: generation, loop: true} = state
      )
      when is_map(sinks) and map_size(sinks) > 0 do
    if Enum.all?(sinks, fn {id, sink} -> is_binary(id) and is_pid(sink) end) do
      case advance(reconcile_sinks(state, sinks)) do
        {:noreply, state} -> {:reply, :ok, state}
        {:stop, reason, state} -> {:stop, reason, :ok, state}
      end
    else
      {:reply, {:error, :invalid_sinks}, state}
    end
  end

  def handle_call({:reconcile, _scope, _sinks}, _from, state),
    do: {:reply, {:error, :stale_episode}, state}

  @impl true
  def handle_cast(:pause, %{mode: :playing} = state) do
    state = interrupt_run(state)
    notify(state, {:paused, div(state.offset, 2)})
    {:noreply, %{state | mode: :paused}}
  end

  def handle_cast(:resume, %{mode: :paused} = state),
    do: {:noreply, start_run(%{state | mode: :playing})}

  def handle_cast(:stop, %{mode: mode} = state) when mode in [:playing, :finishing] do
    finish_stopped(interrupt_run(state))
  end

  def handle_cast(:stop, state), do: finish_stopped(state)
  def handle_cast(_message, state), do: {:noreply, state}

  @impl true
  def handle_info({:push_due, correlation}, %{run: %{correlation: correlation}} = state),
    do: {:noreply, push_next(%{state | push_timer: nil})}

  def handle_info(
        {:vxpipe_audio_playback, sink, correlation, {:completed, duration}},
        %{run: %{correlation: correlation}} = state
      )
      when is_integer(duration) and duration >= 0 do
    case Map.fetch(state.pending, sink) do
      {:ok, %{stage: :playback} = pending} ->
        advance(%{state | pending: Map.put(state.pending, sink, %{pending | done?: true})})

      _unrelated ->
        {:noreply, state}
    end
  end

  def handle_info({:request_timeout, token}, %{timer: {token, _timer}} = state),
    do: failed(state, :timeout)

  def handle_info({:DOWN, monitor, :process, pid, _reason}, state)
      when is_map_key(state.monitors, monitor),
      do: output_lost(state, pid)

  def handle_info(message, state) do
    response =
      Enum.find_value(state.pending, fn
        {_sink, %{id: nil}} ->
          nil

        {sink, pending} ->
          case :gen_server.check_response(message, pending.id) do
            :no_reply -> nil
            reply -> {sink, pending, reply}
          end
      end)

    case response do
      nil ->
        {:noreply, state}

      {sink, %{stage: :finish} = pending, {:reply, :ok}} ->
        pending = %{pending | id: nil, stage: :playback, done?: false}
        advance(%{state | pending: Map.put(state.pending, sink, pending)})

      {sink, pending, {:reply, :ok}} ->
        pending = %{pending | id: nil, done?: true}
        advance(%{state | pending: Map.put(state.pending, sink, pending)})

      {sink, _pending, _error} ->
        output_lost(state, sink)
    end
  end

  defp start_run(state) do
    correlation = "#{state.episode_id}:#{state.connection_generation}:#{state.sequence}"
    run = %{correlation: correlation, started_ms: now(), frames: 0}
    push_next(%{state | run: run, cursor: state.offset, sequence: state.sequence + 1})
  end

  defp push_next(%{mode: :playing, pending: pending} = state) when map_size(pending) == 0 do
    case Cursor.next(state.asset.payload, state.cursor, state.loop) do
      :complete ->
        request_all(%{state | mode: :finishing}, :finish, fn _entry ->
          {:vxpipe_audio_output_finish, state.run.correlation, self()}
        end)

      {payload, next_cursor} ->
        if due?(state.run) do
          push(state, payload, next_cursor)
        else
          schedule_push(state)
        end
    end
  end

  defp push_next(state), do: state

  defp due?(run), do: run.frames < @window_frames + div(now() - run.started_ms, @frame_ms)

  defp schedule_push(%{push_timer: nil, run: run} = state) do
    due_at = run.started_ms + (run.frames - @window_frames + 1) * @frame_ms
    delay = max(due_at - now(), 0)
    timer = Process.send_after(self(), {:push_due, run.correlation}, delay)
    %{state | push_timer: timer}
  end

  defp schedule_push(state), do: state

  defp push(state, payload, next_cursor) do
    state =
      request_all(%{state | next_cursor: next_cursor}, :push, fn {connection, _sink} ->
        {:vxpipe_audio_output, frame(state, connection, payload)}
      end)

    if rem(state.run.frames, 50) == 0, do: pressure(state, :queued)
    %{state | run: %{state.run | frames: state.run.frames + 1}}
  end

  # Sends one request to every sink; the batch completes when every sink has answered.
  defp request_all(state, stage, message) do
    pending =
      Map.new(state.sinks, fn {_connection, sink} = entry ->
        {sink, %{id: :gen_server.send_request(sink, message.(entry)), stage: stage, done?: false}}
      end)

    %{state | pending: pending, timer: arm_timeout(state.timer)}
  end

  defp advance(%{pending: pending} = state) when map_size(pending) == 0, do: {:noreply, state}

  defp advance(state) do
    if Enum.all?(state.pending, fn {_sink, pending} -> pending.done? end) do
      stage = state.pending |> Map.values() |> hd() |> Map.fetch!(:stage)
      complete_stage(stage, %{state | pending: %{}, timer: cancel(state.timer)})
    else
      {:noreply, state}
    end
  end

  defp complete_stage(:push, state),
    do: {:noreply, push_next(%{state | cursor: state.next_cursor})}

  defp complete_stage(:playback, state) do
    state =
      request_all(%{state | mode: :draining}, :drain, fn _entry ->
        :vxpipe_audio_output_drain
      end)

    pressure(state, :draining)
    {:noreply, state}
  end

  defp complete_stage(:drain, state) do
    stop_timing(state, :ok)
    notify(state, :completed)
    {:stop, :normal, state}
  end

  # Interrupts the current run on every sink. The minimum played duration becomes the new
  # cursor, so a resumed run never skips audio a listener has not heard.
  defp interrupt_run(%{run: nil} = state), do: state

  defp interrupt_run(state) do
    _ = cancel(state.push_timer)
    _ = cancel(state.timer)

    played_ms =
      if state.run.frames == 0 do
        0
      else
        state.sinks
        |> Map.values()
        |> Enum.flat_map(fn sink ->
          case interrupt(sink, state.run.correlation) do
            {:ok, played} when is_integer(played) and played >= 0 -> [played]
            _other -> []
          end
        end)
        |> Enum.min(fn -> 0 end)
      end

    Enum.each(state.pending, fn
      {_sink, %{id: nil}} -> :ok
      {_sink, %{id: id}} -> :gen_server.receive_response(id, 0)
    end)

    %{
      state
      | offset: advance_offset(state, played_ms * @bytes_per_ms),
        run: nil,
        pending: %{},
        timer: nil,
        push_timer: nil
    }
  end

  defp interrupt(sink, correlation) do
    GenServer.call(
      sink,
      {:vxpipe_audio_output_interrupt, correlation, self()},
      @interrupt_timeout_ms
    )
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp advance_offset(%{loop: true} = state, bytes),
    do: rem(state.offset + bytes, byte_size(state.asset.payload))

  defp advance_offset(state, bytes),
    do: min(state.offset + bytes, byte_size(state.asset.payload))

  defp finish_stopped(state) do
    _ = cancel(state.push_timer)
    _ = cancel(state.timer)
    stop_timing(state, :cancelled)
    notify(%{state | pending: %{}}, :stopped)
    {:stop, :normal, state}
  end

  defp output_lost(%{loop: true, owner: owner} = state, sink) when sink != owner do
    sinks = Map.reject(state.sinks, fn {_connection, output} -> output == sink end)

    if map_size(sinks) > 0 and map_size(sinks) < map_size(state.sinks),
      do: advance(reconcile_sinks(state, sinks)),
      else: failed(state)
  end

  defp output_lost(state, _sink), do: failed(state)

  defp reconcile_sinks(state, sinks) do
    retained = [state.owner | Map.values(sinks)]

    monitors =
      Map.filter(state.monitors, fn {reference, pid} ->
        if pid in retained do
          true
        else
          Process.demonitor(reference, [:flush])
          false
        end
      end)

    monitors =
      Enum.reduce(retained -- Map.values(monitors), monitors, fn pid, monitors ->
        Map.put(monitors, Process.monitor(pid), pid)
      end)

    pending =
      Map.filter(state.pending, fn {sink, pending} ->
        if sink in Map.values(sinks) do
          true
        else
          if pending.id, do: :gen_server.receive_response(pending.id, 0)
          false
        end
      end)

    %{state | sinks: sinks, monitors: monitors, pending: pending}
  end

  defp frame(state, connection, payload) do
    %AudioOutputFrame{
      tenant_id: state.tenant_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      participant_id: state.participant_id,
      connection_id: connection,
      command_id: state.episode_id,
      correlation_id: state.run.correlation,
      codec: :linear16,
      sample_rate: 48_000,
      channels: 1,
      byte_order: :little,
      payload: payload,
      audio_scope: :private,
      output_generation: state.output_generation,
      reply_to: self()
    }
  end

  defp failed(state, outcome \\ :failed) do
    _ = cancel(state.push_timer)
    _ = cancel(state.timer)
    stop_timing(state, outcome)
    notify(state, {:failed, :output_unavailable})
    {:stop, :normal, state}
  end

  defp arm_timeout(previous) do
    _ = cancel(previous)
    token = make_ref()
    {token, Process.send_after(self(), {:request_timeout, token}, @request_timeout_ms)}
  end

  defp cancel(nil), do: nil
  defp cancel({_token, timer}), do: cancel(timer)

  defp cancel(timer) when is_reference(timer) do
    _ = Process.cancel_timer(timer)
    nil
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp notify(state, status) do
    observation =
      case status do
        {:paused, _position} -> :paused
        {:failed, _reason} -> :failed
        terminal -> terminal
      end

    pressure(state, observation)
    send(state.owner, {:vxpipe_wait_playback, self(), state.episode_id, status})
  end

  defp pressure(state, status) do
    kind = if state.loop, do: :wait, else: :cue
    Telemetry.wait_sound_pressure(kind, status, map_size(state.pending), map_size(state.sinks))
  end

  defp stop_timing(%{loop: false} = state, outcome),
    do: Telemetry.transfer_phase_stop(state.started_at, :cue, outcome)

  defp stop_timing(_state, _outcome), do: :ok
end
