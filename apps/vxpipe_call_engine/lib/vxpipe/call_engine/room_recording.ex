defmodule Vxpipe.CallEngine.RoomRecording do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.RoomMixer

  alias Vxpipe.CallEngine.RoomRecording.{
    Configuration,
    PolicyPreparation,
    Preparation,
    Readiness,
    State,
    Streams
  }

  @call_timeout 1_000

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))

  def ref(incarnation_id),
    do: {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:room_recording, incarnation_id}}}

  def whereis(incarnation_id), do: GenServer.whereis(ref(incarnation_id))

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :incarnation_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @spec stats(GenServer.server()) :: map() | {:error, :unavailable}
  def stats(recording), do: safe_call(recording, :stats)

  @impl Vxpipe.CallEngine.Readiness.Adapter
  defdelegate readiness(recording), to: Readiness

  @impl Vxpipe.CallEngine.Readiness.Adapter
  def readiness_binding(%{instance: recording, binding: {_id, :prepared_policy, token}}),
    do: Readiness.prepared_readiness(recording, token)

  def readiness_binding(%{instance: recording}), do: readiness(recording)

  def prepare_policy(recording, candidate, tracks, options),
    do: PolicyPreparation.request(recording, candidate, tracks, options)

  def discard_policy(recording, token), do: safe_call(recording, {:discard_policy, token})

  @doc "Returns the recorder and its required local writers/subscriptions for lifecycle monitoring."
  defdelegate readiness_resources(recording), to: Readiness, as: :resources

  @doc "Prepares the complete demanded recording track set under the installed recording interval."
  def prepare_tracks(recording, tracks, interval) do
    safe_call(recording, {:prepare_tracks, tracks, interval})
  end

  @impl true
  def init(options) do
    with {:ok, configuration} <- Configuration.new(options),
         {:ok, format} <- RoomMixer.ingress_configuration(configuration.mixer),
         {:ok, streams} <- Streams.open(configuration, format, self()) do
      {:ok,
       %State{
         configuration: configuration,
         format: format,
         readiness_resource: Resource.new(:recording, :room, __MODULE__, configuration),
         mixer_monitor: Process.monitor(configuration.mixer),
         streams: streams,
         accepted_chunks: 0,
         rejected_chunks: 0
       }}
    else
      {:error, reason} -> {:stop, reason}
      _invalid -> {:stop, :invalid_room_recording_options}
    end
  end

  @impl true
  def handle_call(:readiness_binding, _from, state) do
    {:reply, {:ok, PolicyPreparation.current_binding(state)}, state}
  end

  def handle_call(:preparation_configuration, _from, state),
    do: {:reply, {:ok, state.configuration}, state}

  def handle_call({:prepared_readiness_binding, token}, _from, state),
    do: {:reply, PolicyPreparation.binding(state, token), state}

  def handle_call(
        {:confirm_prepared_recording, token, binding, resource, status, dependencies},
        _from,
        state
      ) do
    case PolicyPreparation.confirm(state, token, binding, resource, status, dependencies) do
      {:ok, state} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:prepare_policy, candidate, tracks, subscriptions, options}, _from, state) do
    case PolicyPreparation.begin(state, candidate, tracks, subscriptions, options) do
      {:ok, token, state} -> {:reply, {:ok, token}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:discard_policy, token}, _from, state) do
    case PolicyPreparation.discard(state, token) do
      {:ok, state} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:vxpipe_apply_media_policy, snapshot}, _from, state) do
    with {:ok, snapshot} <- Snapshot.prepare(snapshot, state.policy),
         {:ok, state} <- PolicyPreparation.install(state, snapshot) do
      {:reply, :ok, %{state | policy: snapshot}}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:prepare_tracks, tracks, interval}, _from, %{pending_policy: nil} = state) do
    case Preparation.prepare(state, tracks, interval) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:prepare_tracks, _tracks, _interval}, _from, state),
    do: {:reply, {:error, :preparation_conflict}, state}

  def handle_call(:stats, _from, state) do
    stats = %{
      accepted_chunks: state.accepted_chunks,
      rejected_chunks: state.rejected_chunks,
      streams: Streams.count(state.streams)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(
        {:vxpipe_room_audio_available, mixer, id},
        %{configuration: %{mixer: mixer}} = state
      ) do
    case Map.fetch(state.streams, id) do
      {:ok, stream_state} -> pull_stream(state, id, stream_state)
      :error -> {:noreply, state}
    end
  end

  def handle_info({:recording_policy_expired, token}, %{pending_policy: %{token: token}} = state),
    do: {:noreply, PolicyPreparation.fail(state)}

  def handle_info(
        {:DOWN, monitor, :process, mixer, reason},
        %{configuration: %{mixer: mixer}, mixer_monitor: monitor} = state
      ) do
    {:stop, {:shutdown, {:room_mixer_unavailable, reason}}, state}
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{pending_policy: pending} = state)
      when not is_nil(pending) do
    if monitor == pending.monitor or Map.has_key?(pending.monitors, monitor),
      do: {:noreply, PolicyPreparation.fail(state)},
      else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp pull_stream(state, id, stream_state) do
    case Streams.pull(stream_state, state.configuration) do
      {:ok, stream_state, accepted, rejected} ->
        state = %{
          state
          | streams: Map.put(state.streams, id, stream_state),
            accepted_chunks: state.accepted_chunks + accepted,
            rejected_chunks: state.rejected_chunks + rejected
        }

        {:noreply, state}

      {:error, _reason} ->
        {:stop, {:shutdown, :recording_subscription_unavailable}, state}
    end
  end

  defp safe_call(server, message) do
    try do
      GenServer.call(server, message, @call_timeout)
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end
end
