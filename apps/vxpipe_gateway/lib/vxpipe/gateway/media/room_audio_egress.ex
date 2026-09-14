defmodule Vxpipe.Gateway.Media.RoomAudioEgress do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  alias Vxpipe.Gateway.Media.RoomAudioEgress.{
    Delivery,
    OutputGate,
    PipelineLifecycle,
    PolicyPreparation,
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

  @spec activate(pid()) :: :ok | {:error, term()}
  def activate(egress), do: safe_call(egress, :activate)

  @spec await_ready(pid()) :: :ok | {:error, term()}
  def await_ready(egress), do: safe_call(egress, :await_ready)

  def hold(egress, generation), do: OutputGate.change(egress, :hold, generation)
  def release(egress, generation), do: OutputGate.change(egress, :release, generation)

  @impl true
  def readiness(egress), do: Readiness.readiness(egress)

  def readiness_resources(egress), do: Readiness.resources(egress)

  @impl true
  def readiness_binding(resource), do: Readiness.readiness_binding(resource)

  def prepare_policy(egress, candidate, subscription, options),
    do: PolicyPreparation.request(egress, candidate, subscription, options)

  def discard_policy(egress, token), do: safe_call(egress, {:discard_policy, token})

  @impl true
  def init(options), do: {:ok, State.new(options)}

  @impl true
  def handle_call({:adopt_attachment, attachment}, {owner, _}, %{owner: owner} = state),
    do: {:reply, :ok, %{state | attachment: attachment}}

  def handle_call(:readiness_binding, _from, state) do
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

  def handle_call(:output_gate_binding, _from, state),
    do: {:reply, OutputGate.binding(state), state}

  def handle_call({:output_preparation_binding, candidate, subscription, options}, _from, state),
    do:
      {:reply, PolicyPreparation.preparation_binding(state, candidate, subscription, options),
       state}

  def handle_call({:prepare_policy, candidate, subscription, options}, _from, state) do
    case PolicyPreparation.begin(state, candidate, subscription, options) do
      {:ok, prepared, state} -> {:reply, {:ok, prepared}, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:discard_policy, token}, _from, state) do
    case PolicyPreparation.discard(state, token) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  def handle_call({:policy_readiness_binding, token}, _from, state),
    do: {:reply, PolicyPreparation.binding(state, token), state}

  def handle_call(
        {:confirm_policy_readiness, token, binding, resource, status, dependencies},
        _from,
        state
      ) do
    case PolicyPreparation.confirm(state, token, binding, resource, status, dependencies) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

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
    with {:ok, snapshot} <- Snapshot.prepare(snapshot, state.policy),
         {:ok, reply_mode, state} <- install_policy(snapshot, from, state) do
      send(self(), :drain_room_audio)
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
  def handle_cast(:output_release_failed, state),
    do: stop_unavailable(:output_release_uncertain, state)

  @impl true
  def handle_info(:drain_room_audio, state), do: continue(state)

  def handle_info({:output_policy_expired, token}, %{pending_policy: %{token: token}} = state),
    do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{pending_policy: %{monitor: monitor}} = state
      ),
      do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:DOWN, monitor, :process, _pid, _reason},
        %{pending_policy: %{pipeline: %{pipeline_monitor: monitor}}} = state
      ),
      do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:vxpipe_room_subscription_cancelled, _mixer, id, token},
        %{pending_policy: %{subscription: %{id: id, token: token}}} = state
      ),
      do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:vxpipe_room_audio_output_ready, id},
        %{pending_policy: %{pipeline: %{pipeline_id: id}}} = state
      ),
      do: {:noreply, PolicyPreparation.pipeline_ready(state)}

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

  defp install_policy(snapshot, from, state) do
    case PolicyPreparation.install(state, snapshot) do
      {:continue, state} -> install_live_policy(snapshot, from, state)
      {:ok, state} -> {:ok, :immediate, state}
      {:error, reason, state} -> {:error, reason, state}
    end
  end

  defp install_live_policy(snapshot, _from, %{policy: nil} = state) do
    {:ok, :immediate, %{state | policy: snapshot}}
  end

  defp install_live_policy(snapshot, _from, %{pipeline_pid: nil} = state),
    do: {:ok, :immediate, %{state | policy: snapshot}}

  defp install_live_policy(snapshot, from, state) do
    participant = state.identity.participant_id

    if Snapshot.interval(snapshot, :audio_output, participant) ==
         Snapshot.interval(state.policy, :audio_output, participant) do
      {:ok, :immediate, %{state | policy: snapshot}}
    else
      replace_pipeline(snapshot, from, state)
    end
  end

  defp replace_pipeline(snapshot, from, state) do
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
