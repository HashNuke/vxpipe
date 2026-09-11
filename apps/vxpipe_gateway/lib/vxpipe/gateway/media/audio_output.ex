defmodule Vxpipe.Gateway.Media.AudioOutput do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.AudioOutputFrame
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.Gateway.Media.EgressAcceptance

  alias Vxpipe.Gateway.Media.AudioOutput.{
    Buffering,
    Delivery,
    PipelineLifecycle,
    State,
    Validation
  }

  @call_timeout 5_000
  @frame_duration_ms 20

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec start_pipeline(pid()) :: :ok | {:error, term()}
  def start_pipeline(output), do: safe_call(output, :start_pipeline)

  @spec await_ready(pid()) :: :ok | {:error, term()}
  def await_ready(output), do: safe_call(output, :await_ready)

  @spec push(pid(), AudioOutputFrame.t()) :: :ok | {:error, term()}
  def push(output, frame), do: safe_call(output, {:vxpipe_audio_output, frame})

  @spec finish(pid(), String.t(), pid()) :: :ok | {:error, term()}
  def finish(output, turn, callback) do
    safe_call(output, {:vxpipe_audio_output_finish, turn, callback})
  end

  @spec interrupt(pid(), String.t(), pid()) :: {:ok, non_neg_integer()} | {:error, term()}
  def interrupt(output, turn, callback) do
    safe_call(output, {:vxpipe_audio_output_interrupt, turn, callback})
  end

  @impl true
  def init(options), do: {:ok, State.new(options)}

  @impl true
  def handle_call(:start_pipeline, _from, %{pipeline_pid: nil} = state) do
    case PipelineLifecycle.launch(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:start_pipeline, _from, state), do: {:reply, {:error, :already_started}, state}

  def handle_call(:await_ready, _from, %{pipeline_ready?: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:await_ready, from, state) do
    {:noreply, %{state | ready_waiters: [from | state.ready_waiters]}}
  end

  def handle_call(
        {:vxpipe_bind_recording_egress, %EgressHandoff{} = handoff},
        _from,
        %{current: nil, recording_egress: nil} = state
      ) do
    {:reply, :ok, %{state | recording_egress: handoff}}
  end

  def handle_call({:vxpipe_bind_recording_egress, %EgressHandoff{}}, _from, state) do
    {:reply, {:error, :recording_already_bound}, state}
  end

  def handle_call(
        {:vxpipe_audio_output, %AudioOutputFrame{} = frame},
        from,
        %{pending_push: nil} = state
      ) do
    with :ok <- Validation.frame(frame, state),
         {:ok, state} <- Validation.establish_turn(frame, state) do
      accept_push(state.remainder <> frame.payload, from, %{state | remainder: <<>>})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output, %AudioOutputFrame{}}, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(
        {:vxpipe_audio_output_finish, turn, callback},
        from,
        %{pending_finish: nil, pending_push: nil} = state
      ) do
    with :ok <- Validation.turn(turn, callback, state) do
      prepare_finish(from, state)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_audio_output_finish, _turn, _callback}, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:vxpipe_audio_output_interrupt, turn, callback}, _from, state) do
    with :ok <- Validation.turn(turn, callback, state),
         played_ms <- state.current.played_frames * @frame_duration_ms,
         state <- reply_pending(state),
         {:ok, state} <- PipelineLifecycle.replace(reset_playback(state)) do
      {:reply, {:ok, played_ms}, state}
    else
      {:error, reason, state} -> {:reply, {:error, reason}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_audio_output_pipeline_ready, pipeline_id},
        %{pipeline_id: pipeline_id} = state
      ) do
    Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))
    continue(%{state | pipeline_ready?: true, ready_waiters: []})
  end

  def handle_info(
        {:vxpipe_audio_output_pipeline_sent, pipeline_id, timestamp},
        %{pipeline_id: pipeline_id, in_flight: %{timestamp: timestamp}} = state
      ) do
    state = state |> acknowledge_playout() |> drain_pending_push() |> drain_pending_finish()
    continue(state)
  end

  def handle_info(
        {:vxpipe_audio_output_pipeline_unavailable, pipeline_id, reason},
        %{pipeline_id: pipeline_id} = state
      ) do
    stop_unavailable(reason, state)
  end

  def handle_info(
        {:DOWN, monitor, :process, _pipeline, reason},
        %{pipeline_monitor: monitor} = state
      ) do
    stop_unavailable(reason, PipelineLifecycle.clear_pipeline(state))
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp accept_push(pcm, from, state) do
    case Buffering.accept(pcm, state) do
      {:accepted, state} ->
        reply_after_drain(:ok, state)

      {:backpressure, pending, state} ->
        noreply_after_drain(%{state | pending_push: %{from: from, pcm: pending}})
    end
  end

  defp prepare_finish(from, state) do
    case Buffering.finish(state) do
      {:ok, state} -> reply_after_drain(:ok, state)
      {:backpressure, state} -> noreply_after_drain(%{state | pending_finish: %{from: from}})
    end
  end

  defp drain_pending_push(%{pending_push: nil} = state), do: state

  defp drain_pending_push(state) do
    pending = state.pending_push

    case Buffering.accept(pending.pcm, %{state | pending_push: nil}) do
      {:accepted, state} ->
        GenServer.reply(pending.from, :ok)
        state

      {:backpressure, pcm, state} ->
        %{state | pending_push: %{pending | pcm: pcm}}
    end
  end

  defp drain_pending_finish(%{pending_finish: nil} = state), do: state
  defp drain_pending_finish(%{pending_push: pending} = state) when not is_nil(pending), do: state

  defp drain_pending_finish(state) do
    pending = state.pending_finish

    case Buffering.finish(%{state | pending_finish: nil}) do
      {:ok, state} ->
        GenServer.reply(pending.from, :ok)
        state

      {:backpressure, state} ->
        %{state | pending_finish: pending}
    end
  end

  defp acknowledge_playout(state) do
    current = state.current

    :ok =
      EgressAcceptance.record(
        state.recording_egress,
        current,
        state.connection_id,
        state.in_flight.payload
      )

    current =
      if current.started? do
        %{current | played_frames: current.played_frames + 1}
      else
        send(current.callback, {:vxpipe_audio_playback, self(), current.correlation_id, :started})
        %{current | played_frames: 1, started?: true}
      end

    %{state | current: current, in_flight: nil}
  end

  defp continue(state) do
    state = maybe_notify_progress(state)

    case Delivery.drain(state) do
      {:ok, state} -> {:noreply, maybe_complete(state)}
      {:error, reason, state} -> stop_unavailable(reason, state)
    end
  end

  defp reply_after_drain(reply, state) do
    case Delivery.drain(state) do
      {:ok, state} -> {:reply, reply, maybe_complete(state)}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  defp noreply_after_drain(state) do
    case Delivery.drain(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason, state} -> stop_unavailable(reason, state)
    end
  end

  defp maybe_notify_progress(%{current: %{finished?: true, started?: true} = current} = state) do
    due? =
      current.played_frames > current.last_progress_frames and
        current.played_frames < current.frame_count and
        current.played_frames - current.last_progress_frames >= state.progress_interval_frames

    if due? do
      send(
        current.callback,
        {:vxpipe_audio_playback, self(), current.correlation_id,
         {:progress, current.played_frames * @frame_duration_ms,
          current.frame_count * @frame_duration_ms}}
      )

      %{state | current: %{current | last_progress_frames: current.played_frames}}
    else
      state
    end
  end

  defp maybe_notify_progress(state), do: state

  defp maybe_complete(%{current: %{finished?: true} = current} = state) do
    if is_nil(state.in_flight) and :queue.is_empty(state.queue) do
      send(
        current.callback,
        {:vxpipe_audio_playback, self(), current.correlation_id,
         {:completed, current.played_frames * @frame_duration_ms}}
      )

      clear_turn(state)
    else
      state
    end
  end

  defp maybe_complete(state), do: state

  defp clear_turn(state) do
    %{
      state
      | current: nil,
        in_flight: nil,
        pending_finish: nil,
        pending_push: nil,
        queue: :queue.new(),
        remainder: <<>>
    }
  end

  defp reset_playback(state) do
    state
    |> clear_turn()
    |> Map.put(:next_sequence_number, 0)
  end

  defp reply_pending(state) do
    if state.pending_push, do: GenServer.reply(state.pending_push.from, {:error, :interrupted})

    if state.pending_finish,
      do: GenServer.reply(state.pending_finish.from, {:error, :interrupted})

    state
  end

  defp stop_unavailable(reason, state) do
    send(state.owner, {:vxpipe_connection_unavailable, {:audio_output, reason}})
    {:stop, :audio_output_unavailable, state}
  end

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
