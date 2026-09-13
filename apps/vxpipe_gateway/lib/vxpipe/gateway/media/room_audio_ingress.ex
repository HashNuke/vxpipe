defmodule Vxpipe.Gateway.Media.RoomAudioIngress do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.Media.PCMFrame

  alias Vxpipe.Gateway.Media.RoomAudioIngress.{
    FrameProjection,
    PipelineLifecycle,
    Readiness,
    State
  }

  @call_timeout 5_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec start_pipeline(pid()) :: :ok | {:error, term()}
  def start_pipeline(ingress), do: safe_call(ingress, :start_pipeline)

  @spec push(pid() | nil, Vxpipe.CallEngine.Media.AudioFrame.t()) ::
          :ok | :disabled | {:error, term()}
  def push(nil, _frame), do: :disabled
  def push(ingress, frame), do: safe_call(ingress, {:push, frame})

  @spec await_ready(pid()) :: :ok | {:error, term()}
  def await_ready(ingress), do: safe_call(ingress, :await_ready)

  @impl true
  def readiness(server), do: Readiness.readiness(server)
  def readiness_resources(server), do: Readiness.resources(server)
  def prepare_track(server, track), do: Readiness.prepare_track(server, track)

  @impl true
  def init(options), do: {:ok, State.new(options)}

  @impl true
  def handle_call(:readiness_binding, _from, state) do
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

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

  def handle_call({:push, _frame}, _from, %{policy: nil} = state) do
    {:reply, {:error, :policy_unavailable}, state}
  end

  def handle_call({:push, frame}, _from, state) do
    cond do
      FrameProjection.stale_transport_frame?(frame, state) ->
        {:reply, {:error, :stale_policy_interval}, state}

      is_nil(state.pipeline_id) ->
        {:reply, {:error, :pipeline_unavailable}, state}

      true ->
        {:reply, safe_pipeline_push(state.pipeline, state.pipeline_id, frame), state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, from, state) do
    case Snapshot.prepare(snapshot, state.policy) do
      {:ok, snapshot} when is_nil(state.policy) ->
        {:reply, :ok, %{state | policy: snapshot}}

      {:ok, snapshot} ->
        participant = state.identity.participant_id

        if Snapshot.interval(snapshot, :audio_input, participant) ==
             Snapshot.interval(state.policy, :audio_input, participant) do
          {:reply, :ok, %{state | policy: snapshot}}
        else
          replace_pipeline(snapshot, from, state)
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state) do
    {:reply, {:error, :invalid_policy}, state}
  end

  @impl true
  def handle_info(
        {:vxpipe_audio_pipeline, pipeline_id, %PCMFrame{} = pcm_frame},
        %{pipeline_id: pipeline_id, policy: %Snapshot{} = policy} = state
      ) do
    sequence_number = state.next_sequence_number
    revision = Snapshot.interval(policy, :audio_input, state.identity.participant_id)
    frame = FrameProjection.normalized(pcm_frame, sequence_number, revision)
    state = %{state | next_sequence_number: sequence_number + 1}

    case state.engine.push_room_audio(state.attachment, frame) do
      :ok ->
        {:noreply, state}

      {:error, reason}
      when reason in [
             :buffer_full,
             :duplicate_frame,
             :stale_policy_revision,
             :stale_sequence,
             :stale_timestamp
           ] ->
        {:noreply, state}

      {:error, reason} ->
        notify_unavailable(state.owner, reason)
        {:stop, :room_audio_unavailable, state}
    end
  end

  def handle_info({:vxpipe_audio_pipeline, _stale_pipeline_id, %PCMFrame{}}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:vxpipe_audio_pipeline_ready, pipeline_id},
        %{pipeline_id: pipeline_id} = state
      ) do
    Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))
    {:noreply, %{state | pipeline_ready?: true, ready_waiters: []}}
  end

  def handle_info({:vxpipe_audio_pipeline_ready, _pipeline_id}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, _pipeline, reason},
        %{pipeline_monitor: monitor} = state
      ) do
    notify_unavailable(state.owner, reason)
    {:stop, :audio_pipeline_unavailable, PipelineLifecycle.clear(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp replace_pipeline(snapshot, from, state) do
    case PipelineLifecycle.replace(state) do
      {:ok, state} ->
        {:noreply,
         %{
           state
           | policy: snapshot,
             ready_waiters: [from | state.ready_waiters],
             reject_received_through_ms: state.clock.()
         }}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp safe_pipeline_push(pipeline, pipeline_id, frame) do
    pipeline.push(pipeline_id, frame)
  catch
    :exit, _reason -> {:error, :pipeline_unavailable}
  end

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp notify_unavailable(owner, reason) do
    send(owner, {:vxpipe_connection_unavailable, {:room_audio, reason}})
  end
end
