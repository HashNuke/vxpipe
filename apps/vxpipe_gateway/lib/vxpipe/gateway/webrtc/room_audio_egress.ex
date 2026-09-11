defmodule Vxpipe.Gateway.WebRTC.RoomAudioEgress do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.Gateway.WebRTC.RoomAudioEgress.{Delivery, PipelineLifecycle, State}

  @call_timeout 5_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :connection_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec activate(pid()) :: :ok | {:error, term()}
  def activate(egress), do: safe_call(egress, :activate)

  @spec await_ready(pid()) :: :ok | {:error, term()}
  def await_ready(egress), do: safe_call(egress, :await_ready)

  @impl true
  def init(options), do: {:ok, State.new(options)}

  @impl true
  def handle_call(:activate, _from, %{pipeline_pid: nil, subscription: nil} = state) do
    case PipelineLifecycle.launch(state) do
      {:ok, launched_state} ->
        finish_activation(launched_state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:activate, _from, state), do: {:reply, {:error, :already_started}, state}

  def handle_call(:await_ready, _from, %{pipeline_ready?: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:await_ready, from, state) do
    {:noreply, %{state | ready_waiters: [from | state.ready_waiters]}}
  end

  def handle_call({:vxpipe_apply_media_policy, %Snapshot{} = snapshot}, from, state) do
    with :ok <- Snapshot.validate_transition(snapshot, state.policy),
         {:ok, reply_mode, state} <- install_policy(snapshot, from, state),
         {:ok, state} <- Delivery.drain(state) do
      policy_reply(reply_mode, state)
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, _invalid}, _from, state) do
    {:reply, {:error, :invalid_policy}, state}
  end

  @impl true
  def handle_info(
        {:vxpipe_room_audio_output_ready, pipeline_id},
        %{pipeline_id: pipeline_id} = state
      ) do
    Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))
    continue(%{state | pipeline_ready?: true, ready_waiters: []})
  end

  def handle_info(
        {:vxpipe_room_audio_available, _mixer, subscription_id},
        %{subscription_id: subscription_id} = state
      ) do
    continue(%{state | drain_pending?: true})
  end

  def handle_info(
        {:vxpipe_room_audio_output_sent, pipeline_id, timestamp},
        %{in_flight: {pipeline_id, timestamp}} = state
      ) do
    continue(%{state | in_flight: nil})
  end

  def handle_info(
        {:vxpipe_room_audio_output_unavailable, pipeline_id, reason},
        %{pipeline_id: pipeline_id} = state
      ) do
    stop_unavailable(reason, state)
  end

  def handle_info(
        {:DOWN, monitor, :process, _pipeline, reason},
        %{pipeline_monitor: monitor} = state
      ) do
    stop_unavailable(reason, PipelineLifecycle.clear(state))
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp subscribe(state) do
    state.engine.subscribe_room_audio(state.attachment,
      id: state.subscription_id,
      tenant_id: state.identity.tenant_id,
      room_id: state.identity.room_id,
      incarnation_id: state.identity.incarnation_id,
      recipient_participant_id: state.identity.participant_id,
      subscriber: self()
    )
  end

  defp finish_activation(state) do
    case subscribe(state) do
      {:ok, subscription} ->
        {:reply, :ok, %{state | subscription: subscription}}

      {:error, reason} ->
        _ = PipelineLifecycle.stop(state)
        {:reply, {:error, reason}, PipelineLifecycle.clear(state)}
    end
  end

  defp install_policy(snapshot, _from, %{policy: nil} = state) do
    {:ok, :immediate, %{state | policy: snapshot}}
  end

  defp install_policy(snapshot, from, state) do
    case PipelineLifecycle.replace(state) do
      {:ok, state} ->
        {:ok, :when_ready,
         %{state | policy: snapshot, ready_waiters: [from | state.ready_waiters]}}

      {:error, reason, state} ->
        {:error, reason, state}
    end
  end

  defp policy_reply(:immediate, state), do: {:reply, :ok, state}
  defp policy_reply(:when_ready, state), do: {:noreply, state}

  defp continue(state) do
    case Delivery.drain(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason, state} -> stop_unavailable(reason, state)
    end
  end

  defp stop_unavailable(reason, state) do
    send(state.owner, {:vxpipe_connection_unavailable, {:room_audio_output, reason}})
    {:stop, :room_audio_output_unavailable, state}
  end

  defp safe_call(server, message) do
    GenServer.call(server, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
