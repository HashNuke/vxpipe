defmodule Vxpipe.CallEngine.WaitSounds.Player do
  @moduledoc "Independent bounded wait/cue playback driven by actual sink completion."

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.OpeningAudio.Asset
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
                mode: :playing,
                offset: 0,
                next_offset: 0,
                sequence: 0,
                pending: %{},
                monitors: %{},
                correlation: nil,
                timer: nil
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

  @impl true
  def init(options) do
    state = struct!(__MODULE__, Keyword.take(options, @fields ++ [:loop]))

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

          {:ok, %{state | monitors: monitors}, {:continue, :frame}}
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
        notify(state, :completed)
        {:stop, :normal, state}

      {payload, next_offset} ->
        correlation = "#{state.episode_id}:#{state.connection_generation}:#{state.sequence}"

        pending =
          Map.new(state.sinks, fn {connection, sink} ->
            frame = frame(state, connection, correlation, payload)
            id = :gen_server.send_request(sink, {:vxpipe_audio_output, frame})
            {sink, %{id: id, stage: :push, completed?: false}}
          end)

        timer = Process.send_after(self(), {:frame_timeout, correlation}, 5_000)

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
  def handle_cast(:pause, %{mode: :playing} = state), do: {:noreply, %{state | mode: :pausing}}

  def handle_cast(:resume, %{mode: :paused} = state),
    do: {:noreply, %{state | mode: :playing}, {:continue, :frame}}

  def handle_cast(:stop, %{mode: :paused} = state) do
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
    do: failed(state)

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
          notify(state, :stopped)
          {:stop, :normal, state}
      end
    else
      {:noreply, state}
    end
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
      reply_to: self()
    }
  end

  defp failed(state) do
    notify(state, {:failed, :output_unavailable})
    {:stop, :normal, state}
  end

  defp notify(state, status),
    do: send(state.owner, {:vxpipe_wait_playback, self(), state.episode_id, status})
end
