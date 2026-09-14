defmodule Vxpipe.CallEngine.RoomMixer do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame}

  alias Vxpipe.CallEngine.RoomMixer.{
    Configuration,
    Fanout,
    FrameAdmission,
    OpeningGate,
    Playout,
    Policy,
    PolicyPreparation,
    RecordingEgress,
    State,
    Subscription,
    SubscriptionCatalog,
    SubscriptionReadiness,
    TimestampBuffer
  }

  @call_timeout 1_000

  def start_link(options) do
    name = if Keyword.get(options, :register, true), do: via(options), else: nil
    GenServer.start_link(__MODULE__, options, name: name)
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  @spec whereis(String.t()) :: pid() | nil
  def whereis(incarnation_id) when is_binary(incarnation_id) do
    case Registry.lookup(Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)) do
      [{server, _value}] -> server
      [] -> nil
    end
  end

  @doc false
  @spec ref(String.t()) :: GenServer.server()
  def ref(incarnation_id) when is_binary(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, registry_key(incarnation_id)}}
  end

  @spec push(GenServer.server(), NormalizedFrame.t()) :: :ok | {:error, term()}
  def push(server, %NormalizedFrame{} = frame), do: safe_call(server, {:push, frame})

  @doc false
  @spec complete_opening(GenServer.server()) :: :ok | {:error, :unavailable}
  def complete_opening(server), do: safe_call(server, :complete_opening)

  @spec flush_through(GenServer.server(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def flush_through(server, timestamp) when is_integer(timestamp) and timestamp >= 0 do
    safe_call(server, {:flush_through, timestamp})
  end

  @spec subscribe(GenServer.server(), keyword()) :: {:ok, Subscription.t()} | {:error, term()}
  def subscribe(server, options) when is_list(options) do
    safe_call(server, {:subscribe, options})
  end

  @doc false
  @spec subscribe_recording(GenServer.server(), keyword()) ::
          {:ok, Subscription.t()} | {:error, term()}
  def subscribe_recording(server, options) when is_list(options) do
    safe_call(server, {:subscribe_recording, options})
  end

  @doc false
  @spec open_recording_egress(GenServer.server(), String.t()) ::
          :disabled | {:ok, Vxpipe.CallEngine.Recording.EgressHandoff.t()} | {:error, term()}
  def open_recording_egress(server, connection_id) when is_binary(connection_id) do
    safe_call(server, {:open_recording_egress, connection_id})
  end

  @doc false
  @spec take(Subscription.t(), pos_integer()) :: {:ok, [MixedFrame.t()]} | {:error, term()}
  def take(%Subscription{} = subscription, maximum_frames)
      when is_integer(maximum_frames) and maximum_frames > 0 do
    safe_call(
      subscription.mixer,
      {:take, subscription.id, subscription.token, maximum_frames}
    )
  end

  @spec stats(GenServer.server()) :: map() | {:error, :unavailable}
  def stats(server), do: safe_call(server, :stats)

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness(server), do: safe_call(server, :readiness)

  def prepare_policy(server, candidate, options),
    do: PolicyPreparation.request(server, candidate, options)

  def discard_policy(server, token), do: safe_call(server, {:discard_policy, token})

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness_binding(%{instance: server, binding: {:prepared_policy, token}}),
    do: safe_call(server, {:prepared_readiness, token})

  def readiness_binding(%{instance: server}), do: readiness(server)

  @doc false
  def subscription_readiness(server, id, token) do
    safe_call(server, {:subscription_readiness, id, token})
  end

  @doc false
  def recording_configuration(server, token) do
    safe_call(server, {:recording_configuration, token})
  end

  @doc false
  def recording_egress_readiness(server, handoff) do
    safe_call(server, {:recording_egress_readiness, handoff})
  end

  @spec ingress_configuration(GenServer.server()) :: {:ok, map()} | {:error, :unavailable}
  def ingress_configuration(server), do: safe_call(server, :ingress_configuration)

  @impl true
  def init(options) do
    case Configuration.new(options) do
      {:ok, state} -> {:ok, arm_playout(state)}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:readiness, _from, %{policy: nil} = state) do
    {:reply, {:ok, state.readiness_resource, :preparing}, state}
  end

  def handle_call(:readiness, _from, state) do
    resource = PolicyPreparation.resource(state, state.policy)
    {:reply, {:ok, resource, :ready}, state}
  end

  def handle_call({:prepare_policy, candidate, options}, _from, state) do
    case PolicyPreparation.begin(state, candidate, options) do
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

  def handle_call({:prepared_readiness, token}, _from, state),
    do: {:reply, PolicyPreparation.readiness(state, token), state}

  def handle_call({:subscription_readiness, {id, :prepared_policy, lease}, token}, _from, state),
    do: {:reply, PolicyPreparation.subscription_readiness(state, lease, id, token), state}

  def handle_call({:subscription_readiness, id, token}, _from, state) do
    result = SubscriptionReadiness.fetch(state, id, token)
    {:reply, result, state}
  end

  def handle_call({:recording_configuration, token}, _from, state) do
    result =
      if is_reference(token) and token == state.recording_token and not is_nil(state.policy) do
        {:ok,
         %{
           format: state.format,
           interval: state.policy.intervals.recording,
           permitted?: state.policy.effective.record_audio,
           present: state.policy.present_participant_ids
         }}
      else
        {:error, :recording_not_authorized}
      end

    {:reply, result, state}
  end

  def handle_call({:vxpipe_apply_media_policy, snapshot}, _from, state) do
    case Policy.install(state, snapshot) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe, options}, _from, state) do
    with false <- PolicyPreparation.reserved?(state, Keyword.get(options, :id)),
         {:ok, handle, subscriptions} <-
           SubscriptionCatalog.add(
             state.subscriptions,
             options,
             state.identity,
             state.policy,
             self(),
             state.source_sequences
           ) do
      {:reply, {:ok, handle}, %{state | subscriptions: subscriptions}}
    else
      true ->
        {:reply, {:error, :preparation_conflict}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe_recording, options}, _from, state) do
    with false <- PolicyPreparation.reserved?(state, Keyword.get(options, :id)),
         {:ok, handle, subscriptions} <-
           SubscriptionCatalog.add_recording(
             state.subscriptions,
             options,
             state.identity,
             state.policy,
             self(),
             state.recording_token
           ) do
      {:reply, {:ok, handle}, %{state | subscriptions: subscriptions}}
    else
      true ->
        {:reply, {:error, :preparation_conflict}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:push, frame}, _from, state) do
    case FrameAdmission.put(state, frame) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:complete_opening, _from, state) do
    {:reply, :ok, %{state | opening_gate: OpeningGate.open(state.opening_gate)}}
  end

  def handle_call({:open_recording_egress, connection_id}, _from, state) do
    {:reply, RecordingEgress.open(state.recording_egress, self(), connection_id), state}
  end

  def handle_call({:recording_egress_readiness, handoff}, _from, state) do
    {:reply, RecordingEgress.readiness(state.recording_egress, handoff, state.policy), state}
  end

  def handle_call({:flush_through, timestamp}, _from, state) do
    case flush(state, timestamp) do
      {:ok, result, state} -> {:reply, {:ok, result}, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:take, id, token, maximum_frames}, _from, state) do
    {reply, subscriptions} =
      SubscriptionCatalog.take(state.subscriptions, id, token, maximum_frames, self())

    {:reply, reply, %{state | subscriptions: subscriptions}}
  end

  def handle_call(:stats, _from, state) do
    {:reply, state_stats(state), state}
  end

  def handle_call(:ingress_configuration, _from, state) do
    configuration = Map.put(state.format, :clock_origin_ms, state.clock_origin_ms)
    {:reply, {:ok, configuration}, state}
  end

  @impl true
  def handle_info(
        {:vxpipe_room_mixer_tick, tick_ref},
        %{playout: %Playout{tick_ref: tick_ref} = playout} = state
      ) do
    state = %{state | playout: %{playout | tick_ref: nil}}

    state =
      case Playout.due_timestamp(playout, state.buffer.last_flushed_timestamp) do
        {:ok, timestamp} ->
          case flush(state, timestamp) do
            {:ok, _result, state} -> state
            {:error, :stale_timestamp, state} -> state
          end

        :not_due ->
          state
      end

    {:noreply, arm_playout(state)}
  end

  def handle_info({:DOWN, monitor, :process, _subscriber, _reason}, state) do
    subscriptions = SubscriptionCatalog.remove_monitor(state.subscriptions, monitor)
    state = PolicyPreparation.down(%{state | subscriptions: subscriptions}, monitor)
    {:noreply, state}
  end

  def handle_info({:mixer_policy_expired, token}, %{pending_policy: %{token: token}} = state),
    do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info({:mixer_policy_expired, _stale}, state), do: {:noreply, state}

  def handle_info(
        {:vxpipe_recording_egress, handoff, %NormalizedFrame{} = frame},
        state
      ) do
    recording_egress =
      if OpeningGate.admits?(state.opening_gate, frame.timestamp) do
        case RecordingEgress.put(
               state.recording_egress,
               handoff,
               frame,
               state.policy,
               state.subscriptions
             ) do
          {:ok, recording_egress} -> recording_egress
          {:error, _reason, recording_egress} -> recording_egress
        end
      else
        state.recording_egress
      end

    :ok = Vxpipe.CallEngine.Recording.EgressHandoff.release(handoff)
    {:noreply, %{state | recording_egress: recording_egress}}
  end

  defp state_stats(%State{} = state) do
    egress_stats = RecordingEgress.stats(state.recording_egress)

    %{
      buffered_timestamps: map_size(state.buffer.buckets),
      buffer_overflows: state.buffer_overflows,
      policy_dropped_frames: state.policy_dropped_frames,
      policy_revision: policy_revision(state.policy),
      sink_overflows: state.subscriptions.overflows,
      subscriptions: map_size(state.subscriptions.entries),
      recording_egress_buffered_timestamps: egress_stats.buffered_timestamps,
      recording_egress_buffer_overflows: egress_stats.buffer_overflows,
      recording_egress_pending_frames: egress_stats.pending_frames,
      recording_egress_rejected_frames: egress_stats.rejected_frames
    }
  end

  defp policy_revision(nil), do: nil
  defp policy_revision(snapshot), do: snapshot.revision

  defp flush(state, timestamp) do
    case TimestampBuffer.take_through(state.buffer, timestamp) do
      {:ok, buckets, buffer} ->
        case RecordingEgress.take_through(state.recording_egress, timestamp) do
          {:ok, recording_buckets, recording_egress} ->
            {subscriptions, delivered, dropped} =
              Fanout.deliver(
                buckets,
                recording_buckets,
                state.subscriptions,
                state.identity,
                state.format,
                state.policy,
                self()
              )

            result = %{
              delivered: delivered,
              dropped: dropped,
              flushed_timestamps:
                buckets
                |> Kernel.++(recording_buckets)
                |> Enum.map(&elem(&1, 0))
                |> Enum.uniq()
                |> length()
            }

            {:ok, result,
             %{
               state
               | buffer: buffer,
                 recording_egress: recording_egress,
                 subscriptions: subscriptions
             }}

          {:error, reason} ->
            {:error, reason, state}
        end

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp arm_playout(%State{} = state) do
    %{state | playout: Playout.arm(state.playout, self())}
  end

  defp safe_call(server, message) do
    try do
      GenServer.call(server, message, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  defp via(options) do
    options
    |> Keyword.fetch!(:incarnation_id)
    |> ref()
  end

  defp registry_key(incarnation_id), do: {:room_mixer, incarnation_id}
end
