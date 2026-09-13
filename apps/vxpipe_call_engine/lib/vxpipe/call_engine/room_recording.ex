defmodule Vxpipe.CallEngine.RoomRecording do
  @moduledoc false

  use GenServer

  @behaviour Vxpipe.CallEngine.Readiness.Adapter

  alias Vxpipe.CallEngine.Readiness.Resource
  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomRecording.{Configuration, Preparation, Readiness, State, Streams}

  @call_timeout 1_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

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
    {:reply, {:ok, Readiness.binding(state)}, state}
  end

  def handle_call({:prepare_tracks, tracks, interval}, _from, state) do
    case Preparation.prepare(state, tracks, interval) do
      {:ok, state} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

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

  def handle_info(
        {:DOWN, monitor, :process, mixer, reason},
        %{configuration: %{mixer: mixer}, mixer_monitor: monitor} = state
      ) do
    {:stop, {:shutdown, {:room_mixer_unavailable, reason}}, state}
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
