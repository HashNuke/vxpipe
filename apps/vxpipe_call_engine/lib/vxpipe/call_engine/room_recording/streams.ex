defmodule Vxpipe.CallEngine.RoomRecording.Streams do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.MixedFrame
  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}
  alias Vxpipe.CallEngine.RoomMixer

  alias Vxpipe.CallEngine.RoomRecording.{
    Configuration,
    Output,
    SubscriptionState
  }

  @type subscriptions :: %{optional(String.t()) => SubscriptionState.t()}

  @spec open(Configuration.t(), map(), pid()) ::
          {:ok, subscriptions()} | {:error, term()}
  def open(%Configuration{} = configuration, format, source) when is_pid(source) do
    Enum.reduce_while(configuration.targets, {:ok, %{}}, fn target, {:ok, subscriptions} ->
      with {:ok, subscription} <- subscribe(configuration, target, source),
           {:ok, outputs} <- initial_outputs(configuration, target, format, source) do
        state = %SubscriptionState{
          subscription: subscription,
          target: target,
          outputs: outputs
        }

        {:cont, {:ok, Map.put(subscriptions, subscription.id, state)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec count(subscriptions()) :: non_neg_integer()
  def count(subscriptions) do
    Enum.reduce(subscriptions, 0, fn {_id, state}, count ->
      count + map_size(state.outputs)
    end)
  end

  @doc false
  def prepare_output(%SubscriptionState{} = state, mode, format, configuration) do
    if Map.has_key?(state.outputs, mode) do
      {:ok, state}
    else
      with {:ok, stream} <- Stream.new(configuration.identity, mode, format),
           {:ok, handle} <- open_writer(configuration, stream, self()) do
        output = %Output{writer_handle: handle, next_sequence: 0}
        {:ok, put_output(state, mode, output)}
      end
    end
  end

  @spec pull(SubscriptionState.t(), Configuration.t()) ::
          {:ok, SubscriptionState.t(), non_neg_integer(), non_neg_integer()} | {:error, term()}
  def pull(%SubscriptionState{} = state, %Configuration{} = configuration) do
    case RoomMixer.take(state.subscription, configuration.maximum_pull_frames) do
      {:ok, frames} ->
        {state, accepted, rejected} = offer_frames(frames, state, configuration)
        {:ok, state, accepted, rejected}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp offer_frames(frames, state, configuration) do
    Enum.reduce(frames, {state, 0, 0}, fn frame, {state, accepted, rejected} ->
      offer_frame(frame, state, configuration, accepted, rejected)
    end)
  end

  defp offer_frame(%MixedFrame{} = frame, state, configuration, accepted, rejected) do
    with {:ok, output, state} <- output(state, frame, configuration),
         {sequence, output} <- next_sequence(output),
         state = put_output(state, frame.mode, output),
         {:ok, chunk} <- Chunk.from_mixed_frame(frame, sequence) do
      case safe_offer(configuration.writer, output.writer_handle, chunk) do
        :ok -> {state, accepted + 1, rejected}
        {:error, _reason} -> {state, accepted, rejected + 1}
      end
    else
      {:error, _reason} -> {state, accepted, rejected + 1}
    end
  end

  defp output(state, frame, configuration) do
    if is_nil(state.required_modes) or MapSet.member?(state.required_modes, frame.mode) do
      case Map.fetch(state.outputs, frame.mode) do
        {:ok, output} -> {:ok, output, state}
        :error when is_nil(state.required_modes) -> open_output(state, frame, configuration)
        :error -> {:error, :unprepared_recording_track}
      end
    else
      {:error, :unprepared_recording_track}
    end
  end

  defp open_output(state, frame, configuration) do
    with {:ok, stream} <- Stream.new(configuration.identity, frame.mode, frame),
         {:ok, writer_handle} <- open_writer(configuration, stream, self()) do
      output = %Output{writer_handle: writer_handle, next_sequence: 0}
      {:ok, output, put_output(state, frame.mode, output)}
    end
  end

  defp next_sequence(%Output{} = output) do
    {output.next_sequence, %{output | next_sequence: output.next_sequence + 1}}
  end

  defp put_output(state, mode, output) do
    %{state | outputs: Map.put(state.outputs, mode, output)}
  end

  defp initial_outputs(configuration, :full_mix, format, source) do
    with {:ok, stream} <- Stream.new(configuration.identity, :full_mix, format),
         {:ok, writer_handle} <- open_writer(configuration, stream, source) do
      {:ok, %{full_mix: %Output{writer_handle: writer_handle, next_sequence: 0}}}
    end
  end

  defp initial_outputs(_configuration, {:individual_tracks, _participant_ids}, _format, _source),
    do: {:ok, %{}}

  defp subscribe(configuration, target, source) do
    RoomMixer.subscribe_recording(
      configuration.mixer,
      id: subscription_id(target),
      tenant_id: configuration.identity.tenant_id,
      room_id: configuration.identity.room_id,
      incarnation_id: configuration.identity.incarnation_id,
      recording_token: configuration.recording_token,
      mode: target,
      subscriber: source
    )
  end

  defp subscription_id(:full_mix), do: "recording-full-mix"
  defp subscription_id({:individual_tracks, _participant_ids}), do: "recording-individual-tracks"

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
