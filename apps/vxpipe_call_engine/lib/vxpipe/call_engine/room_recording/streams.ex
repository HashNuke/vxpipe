defmodule Vxpipe.CallEngine.RoomRecording.Streams do
  @moduledoc false

  require Logger

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
      reconnection = next_reconnection(state.outputs, mode)

      with {:ok, stream} <-
             Stream.new(
               identity_with_reconnection(configuration, mode, reconnection),
               mode,
               format
             ),
           {:ok, handle} <- open_writer(configuration, stream, self()) do
        log_track_opened(stream, mode)
        output = %Output{writer_handle: handle, next_sequence: 0, reconnection: reconnection}
        {:ok, put_output(state, mode, output)}
      end
    end
  end

  @doc false
  @spec identity_with_reconnection(map(), Stream.mode(), nil | non_neg_integer()) :: map()
  def identity_with_reconnection(
        configuration,
        {:individual_track, participant, _, _},
        reconnection
      ) do
    keys = Map.get(configuration, :participant_keys, %{})

    configuration.identity
    |> Map.put(:participant_key, Map.get(keys, participant))
    |> Map.put(:reconnection, reconnection || 0)
  end

  def identity_with_reconnection(configuration, _mode, _reconnection), do: configuration.identity

  @doc false
  @spec next_reconnection(%{optional(Stream.mode()) => Output.t()}, Stream.mode()) ::
          nil | non_neg_integer()
  def next_reconnection(_outputs, :room_track), do: nil

  def next_reconnection(outputs, {:individual_track, participant, _, _}) do
    smallest_free(used_reconnections(outputs, participant))
  end

  @doc false
  def used_reconnections(outputs, participant) when is_map(outputs) do
    outputs
    |> Map.to_list()
    |> used_reconnections(participant)
  end

  def used_reconnections(entries, participant) when is_list(entries) do
    {integers, has_nil?} =
      Enum.reduce(entries, {[], false}, fn
        {{:individual_track, ^participant, _, _}, %Output{reconnection: reconnection}},
        {ints, nil?} ->
          if is_integer(reconnection),
            do: {[reconnection | ints], nil?},
            else: {ints, true}

        {{:individual_track, ^participant, _, _}, _other}, {ints, _nil?} ->
          {ints, true}

        _other, acc ->
          acc
      end)

    if has_nil? do
      count =
        Enum.count(entries, fn
          {{:individual_track, ^participant, _, _}, _} -> true
          _ -> false
        end)

      fallback =
        if count > 0, do: MapSet.new(0..(count - 1)), else: MapSet.new()

      MapSet.union(MapSet.new(integers), fallback)
    else
      MapSet.new(integers)
    end
  end

  @doc false
  def smallest_free(used) do
    used_set =
      case used do
        %MapSet{} -> used
        list -> MapSet.new(list)
      end

    Enum.find(0..MapSet.size(used_set), &(not MapSet.member?(used_set, &1)))
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
    reconnection = next_reconnection(state.outputs, frame.mode)

    with {:ok, stream} <-
           Stream.new(
             identity_with_reconnection(configuration, frame.mode, reconnection),
             frame.mode,
             frame
           ),
         {:ok, writer_handle} <- open_writer(configuration, stream, self()) do
      log_track_opened(stream, frame.mode)
      output = %Output{writer_handle: writer_handle, next_sequence: 0, reconnection: reconnection}
      {:ok, output, put_output(state, frame.mode, output)}
    end
  end

  defp next_sequence(%Output{} = output) do
    {output.next_sequence, %{output | next_sequence: output.next_sequence + 1}}
  end

  defp put_output(state, mode, output) do
    %{state | outputs: Map.put(state.outputs, mode, output)}
  end

  defp initial_outputs(configuration, :room_track, format, source) do
    with {:ok, stream} <- Stream.new(configuration.identity, :room_track, format),
         {:ok, writer_handle} <- open_writer(configuration, stream, source) do
      {:ok,
       %{room_track: %Output{writer_handle: writer_handle, next_sequence: 0, reconnection: nil}}}
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

  defp subscription_id(:room_track), do: "recording-room-track"
  defp subscription_id({:individual_tracks, _participant_ids}), do: "recording-individual-tracks"

  defp log_track_opened(stream, mode) do
    Logger.info("recording_track_opened",
      tenant_id: stream.tenant_id,
      call_id: stream.call_id,
      room_id: stream.room_id,
      incarnation_id: stream.incarnation_id,
      stream_id: stream.stream_id,
      mode: inspect(mode),
      participant_id: stream.participant_id,
      participant_key: stream.participant_key,
      reconnection: stream.reconnection,
      connection_id: stream.connection_id,
      track_id: stream.track_id
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
