defmodule Vxpipe.CallEngine.WaitSounds.Player do
  @moduledoc "Independent bounded wait/cue playback driven by actual sink completion."

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.OpeningAudio.Asset
  alias Vxpipe.CallEngine.Telemetry
  alias Vxpipe.CallEngine.WaitSounds.Cursor

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
                next_offset: 0,
                sequence: 0,
                pending: %{},
                monitors: %{},
                correlation: nil,
                timer: nil,
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
           {:continue, :frame}}
        else
          {:stop, :invalid_configuration}
        end

      _invalid ->
        {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_continue(:frame, state) do
    case Cursor.next(state.asset.payload, state.offset, state.loop) do
      :complete ->
        pending =
          Map.new(state.sinks, fn {_connection, sink} ->
            id = :gen_server.send_request(sink, :vxpipe_audio_output_drain)
            {sink, %{id: id, stage: :drain, completed?: false}}
          end)

        correlation = "#{state.episode_id}:#{state.connection_generation}:drain"
        timer = Process.send_after(self(), {:frame_timeout, correlation}, 5_000)

        pressure(%{state | pending: pending}, :draining)

        {:noreply,
         %{state | pending: pending, mode: :draining, correlation: correlation, timer: timer}}

      {payload, next_offset} ->
        correlation = "#{state.episode_id}:#{state.connection_generation}:#{state.sequence}"

        pending =
          Map.new(state.sinks, fn {connection, sink} ->
            frame = frame(state, connection, correlation, payload)
            id = :gen_server.send_request(sink, {:vxpipe_audio_output, frame})
            {sink, %{id: id, stage: :push, completed?: false}}
          end)

        timer = Process.send_after(self(), {:frame_timeout, correlation}, 5_000)

        if rem(state.sequence, 50) == 0, do: pressure(%{state | pending: pending}, :queued)

        {:noreply,
         %{
           state
           | pending: pending,
             correlation: correlation,
             next_offset: next_offset,
             sequence: state.sequence + 1,
             timer: timer
         }}
    end
  end

  @impl true
  def handle_call(
        {:reconcile, %{attempt_id: attempt, generation: generation}, sinks},
        _from,
        %{attempt_id: attempt, connection_generation: generation, loop: true} = state
      )
      when is_map(sinks) and map_size(sinks) > 0 do
    if Enum.all?(sinks, fn {id, sink} -> is_binary(id) and is_pid(sink) end) do
      state = reconcile_sinks(state, sinks)

      case if(state.mode == :paused, do: {:noreply, state}, else: advance(state)) do
        {:noreply, state} -> {:reply, :ok, state}
        {:noreply, state, continuation} -> {:reply, :ok, state, continuation}
        {:stop, reason, state} -> {:stop, reason, :ok, state}
      end
    else
      {:reply, {:error, :invalid_sinks}, state}
    end
  end

  def handle_call({:reconcile, _scope, _sinks}, _from, state),
    do: {:reply, {:error, :stale_episode}, state}

  @impl true
  def handle_cast(:pause, %{mode: :playing} = state), do: {:noreply, %{state | mode: :pausing}}

  def handle_cast(:resume, %{mode: :paused} = state),
    do: {:noreply, %{state | mode: :playing}, {:continue, :frame}}

  def handle_cast(:stop, %{mode: :paused} = state) do
    stop_timing(state, :cancelled)
    notify(state, :stopped)
    {:stop, :normal, state}
  end

  def handle_cast(:stop, state), do: {:noreply, %{state | mode: :stopping}}
  def handle_cast(_message, state), do: {:noreply, state}

  @impl true
  def handle_info(
        {:vxpipe_audio_playback, sink, correlation, {:completed, duration}},
        %{correlation: correlation} = state
      )
      when is_integer(duration) and duration >= 0 do
    case Map.fetch(state.pending, sink) do
      {:ok, %{stage: stage} = pending} when stage in [:finish, :playback] ->
        advance(%{state | pending: Map.put(state.pending, sink, %{pending | completed?: true})})

      _unrelated ->
        {:noreply, state}
    end
  end

  def handle_info({:frame_timeout, correlation}, %{correlation: correlation} = state),
    do: failed(state, :timeout)

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when is_map_key(state.monitors, monitor),
      do: failed(state)

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
      {sink, %{stage: :drain}, {:reply, :ok}} ->
        state = %{state | pending: Map.delete(state.pending, sink)}

        if map_size(state.pending) == 0 do
          Process.cancel_timer(state.timer)
          stop_timing(state, if(state.mode == :stopping, do: :cancelled, else: :ok))
          notify(state, if(state.mode == :stopping, do: :stopped, else: :completed))
          {:stop, :normal, state}
        else
          {:noreply, state}
        end

      {sink, %{stage: :push} = pending, {:reply, :ok}} ->
        id =
          :gen_server.send_request(sink, {:vxpipe_audio_output_finish, state.correlation, self()})

        {:noreply,
         %{state | pending: Map.put(state.pending, sink, %{pending | id: id, stage: :finish})}}

      {sink, %{stage: :finish} = pending, {:reply, :ok}} ->
        advance(%{
          state
          | pending: Map.put(state.pending, sink, %{pending | id: nil, stage: :playback})
        })

      nil ->
        {:noreply, state}

      _failed ->
        failed(state)
    end
  end

  defp advance(state) do
    if Enum.all?(state.pending, fn {_sink, pending} ->
         pending.stage == :playback and pending.completed?
       end) do
      Process.cancel_timer(state.timer)
      state = %{state | offset: state.next_offset, pending: %{}, timer: nil, correlation: nil}

      case state.mode do
        :playing ->
          {:noreply, state, {:continue, :frame}}

        :pausing ->
          notify(state, {:paused, div(state.offset, 2)})
          {:noreply, %{state | mode: :paused}}

        :stopping ->
          stop_timing(state, :cancelled)
          notify(state, :stopped)
          {:stop, :normal, state}
      end
    else
      {:noreply, state}
    end
  end

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

  defp frame(state, connection, correlation, payload) do
    %AudioOutputFrame{
      tenant_id: state.tenant_id,
      room_id: state.room_id,
      incarnation_id: state.incarnation_id,
      participant_id: state.participant_id,
      connection_id: connection,
      command_id: state.episode_id,
      correlation_id: correlation,
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
    stop_timing(state, outcome)
    notify(state, {:failed, :output_unavailable})
    {:stop, :normal, state}
  end

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
