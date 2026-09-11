defmodule Vxpipe.CallEngine.RoomRecording do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomRecording.{Configuration, State, Streams}

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

  @impl true
  def init(options) do
    with {:ok, configuration} <- Configuration.new(options),
         {:ok, format} <- RoomMixer.ingress_configuration(configuration.mixer),
         {:ok, streams} <- Streams.open(configuration, format, self()) do
      {:ok,
       %State{
         mixer: configuration.mixer,
         mixer_monitor: Process.monitor(configuration.mixer),
         writer: configuration.writer,
         maximum_pull_frames: configuration.maximum_pull_frames,
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
  def handle_call(:stats, _from, state) do
    stats = %{
      accepted_chunks: state.accepted_chunks,
      rejected_chunks: state.rejected_chunks,
      streams: map_size(state.streams)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:vxpipe_room_audio_available, mixer, id}, %{mixer: mixer} = state) do
    case Map.fetch(state.streams, id) do
      {:ok, stream_state} -> pull_stream(state, id, stream_state)
      :error -> {:noreply, state}
    end
  end

  def handle_info(
        {:DOWN, monitor, :process, mixer, reason},
        %{mixer: mixer, mixer_monitor: monitor} = state
      ) do
    {:stop, {:shutdown, {:room_mixer_unavailable, reason}}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp pull_stream(state, id, stream_state) do
    case Streams.pull(stream_state, state.writer, state.maximum_pull_frames) do
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
