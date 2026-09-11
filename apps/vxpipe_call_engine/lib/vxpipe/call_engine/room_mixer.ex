defmodule Vxpipe.CallEngine.RoomMixer do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Media.{MixedFrame, NormalizedFrame}

  alias Vxpipe.CallEngine.RoomMixer.{
    Configuration,
    Fanout,
    FrameAdmission,
    Policy,
    State,
    Subscription,
    SubscriptionCatalog,
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

  @spec push(GenServer.server(), NormalizedFrame.t()) :: :ok | {:error, term()}
  def push(server, %NormalizedFrame{} = frame), do: safe_call(server, {:push, frame})

  @spec flush_through(GenServer.server(), non_neg_integer()) :: {:ok, map()} | {:error, term()}
  def flush_through(server, timestamp) when is_integer(timestamp) and timestamp >= 0 do
    safe_call(server, {:flush_through, timestamp})
  end

  @spec subscribe(GenServer.server(), keyword()) :: {:ok, Subscription.t()} | {:error, term()}
  def subscribe(server, options) when is_list(options) do
    safe_call(server, {:subscribe, options})
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

  @impl true
  def init(options) do
    case Configuration.new(options) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:vxpipe_apply_media_policy, snapshot}, _from, state) do
    case Policy.install(state, snapshot) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:subscribe, options}, _from, state) do
    case SubscriptionCatalog.add(
           state.subscriptions,
           options,
           state.identity,
           state.policy,
           self(),
           state.source_sequences
         ) do
      {:ok, handle, subscriptions} ->
        {:reply, {:ok, handle}, %{state | subscriptions: subscriptions}}

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

  def handle_call({:flush_through, timestamp}, _from, state) do
    case TimestampBuffer.take_through(state.buffer, timestamp) do
      {:ok, buckets, buffer} ->
        {subscriptions, delivered, dropped} =
          Fanout.deliver(
            buckets,
            state.subscriptions,
            state.identity,
            state.format,
            state.policy,
            self()
          )

        result = %{
          delivered: delivered,
          dropped: dropped,
          flushed_timestamps: length(buckets)
        }

        {:reply, {:ok, result}, %{state | buffer: buffer, subscriptions: subscriptions}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
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

  @impl true
  def handle_info({:DOWN, monitor, :process, _subscriber, _reason}, state) do
    subscriptions = SubscriptionCatalog.remove_monitor(state.subscriptions, monitor)
    {:noreply, %{state | subscriptions: subscriptions}}
  end

  defp state_stats(%State{} = state) do
    %{
      buffered_timestamps: map_size(state.buffer.buckets),
      buffer_overflows: state.buffer_overflows,
      policy_dropped_frames: state.policy_dropped_frames,
      policy_revision: policy_revision(state.policy),
      sink_overflows: state.subscriptions.overflows,
      subscriptions: map_size(state.subscriptions.entries)
    }
  end

  defp policy_revision(nil), do: nil
  defp policy_revision(snapshot), do: snapshot.revision

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
    |> registry_key()
    |> then(&{:via, Registry, {Vxpipe.CallEngine.RoomRegistry, &1}})
  end

  defp registry_key(incarnation_id), do: {:room_mixer, incarnation_id}
end
