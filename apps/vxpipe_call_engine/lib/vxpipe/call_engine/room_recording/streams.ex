defmodule Vxpipe.CallEngine.RoomRecording.Streams do
  @moduledoc false

  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}
  alias Vxpipe.CallEngine.RoomMixer
  alias Vxpipe.CallEngine.RoomRecording.Configuration

  @type stream_state :: Vxpipe.CallEngine.RoomRecording.State.stream_state()

  @spec open(Configuration.t(), map(), pid()) ::
          {:ok, %{optional(String.t()) => stream_state()}} | {:error, term()}
  def open(%Configuration{} = configuration, format, source) when is_pid(source) do
    Enum.reduce_while(configuration.targets, {:ok, %{}}, fn mode, {:ok, streams} ->
      with {:ok, stream} <- Stream.new(configuration.identity, mode, format),
           {:ok, subscription} <- subscribe(configuration, stream, source),
           {:ok, writer_handle} <- open_writer(configuration, stream, source) do
        stream_state = %{
          subscription: subscription,
          writer_handle: writer_handle,
          next_sequence: 0
        }

        {:cont, {:ok, Map.put(streams, subscription.id, stream_state)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec pull(stream_state(), module(), pos_integer()) ::
          {:ok, stream_state(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  def pull(stream_state, writer, maximum_frames) do
    case RoomMixer.take(stream_state.subscription, maximum_frames) do
      {:ok, frames} ->
        {stream_state, accepted, rejected} = offer_frames(frames, stream_state, writer)
        {:ok, stream_state, accepted, rejected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp offer_frames(frames, stream_state, writer) do
    Enum.reduce(frames, {stream_state, 0, 0}, fn frame, {stream_state, accepted, rejected} ->
      sequence = stream_state.next_sequence
      stream_state = %{stream_state | next_sequence: sequence + 1}

      case Chunk.from_mixed_frame(frame, sequence) do
        {:ok, chunk} -> offer_chunk(writer, stream_state, chunk, accepted, rejected)
        {:error, _reason} -> {stream_state, accepted, rejected + 1}
      end
    end)
  end

  defp offer_chunk(writer, stream_state, chunk, accepted, rejected) do
    case safe_offer(writer, stream_state.writer_handle, chunk) do
      :ok -> {stream_state, accepted + 1, rejected}
      {:error, _reason} -> {stream_state, accepted, rejected + 1}
    end
  end

  defp subscribe(configuration, stream, source) do
    RoomMixer.subscribe_recording(
      configuration.mixer,
      id: "recording-#{stream.stream_id}",
      tenant_id: configuration.identity.tenant_id,
      room_id: configuration.identity.room_id,
      incarnation_id: configuration.identity.incarnation_id,
      recording_token: configuration.recording_token,
      mode: stream.mode,
      subscriber: source
    )
  end

  defp open_writer(configuration, stream, source) do
    options = Keyword.put(configuration.writer_options, :source, source)
    safe_open(configuration.writer, stream, options)
  end

  defp safe_open(writer, stream, options) do
    try do
      case writer.open(stream, options) do
        {:ok, _handle} = opened -> opened
        {:error, _reason} = error -> error
        _invalid -> {:error, :invalid_recording_writer_response}
      end
    catch
      _kind, _reason -> {:error, :recording_writer_unavailable}
    end
  end

  defp safe_offer(writer, handle, chunk) do
    try do
      case writer.offer(handle, chunk) do
        :ok -> :ok
        {:error, _reason} = error -> error
        _invalid -> {:error, :invalid_recording_writer_response}
      end
    catch
      _kind, _reason -> {:error, :recording_writer_unavailable}
    end
  end
end
