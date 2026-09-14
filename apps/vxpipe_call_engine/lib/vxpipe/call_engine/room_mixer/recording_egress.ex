defmodule Vxpipe.CallEngine.RoomMixer.RecordingEgress do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer.{SubscriptionCatalog, TimestampBuffer}

  @enforce_keys [
    :buffer,
    :buffer_overflows,
    :capacity,
    :counters,
    :identity,
    :configuration,
    :source_sequences,
    :token
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{}

  @spec new(keyword(), map(), map(), integer(), pos_integer()) ::
          {:ok, nil | t()} | {:error, term()}
  def new(options, identity, format, clock_origin_ms, maximum_timestamps) do
    case Keyword.get(options, :recording_token) do
      token when is_reference(token) ->
        capacity = Keyword.get(options, :maximum_recording_egress_frames, maximum_timestamps)

        if is_integer(capacity) and capacity > 0 do
          counters = EgressHandoff.new_counters()

          {:ok,
           %__MODULE__{
             buffer: TimestampBuffer.new(maximum_timestamps),
             buffer_overflows: 0,
             capacity: capacity,
             counters: counters,
             identity: identity,
             configuration: %{
               channels: format.channels,
               clock: Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end),
               clock_origin_ms: clock_origin_ms,
               frame_samples: format.frame_samples,
               gate: counters,
               sample_rate: format.sample_rate
             },
             source_sequences: %{},
             token: token
           }}
        else
          {:error, {:invalid_room_mixer_option, :maximum_recording_egress_frames}}
        end

      _disabled ->
        {:ok, nil}
    end
  end

  @spec open(nil | t(), pid(), String.t()) ::
          :disabled | {:ok, EgressHandoff.t()} | {:error, term()}
  def open(nil, _receiver, _connection_id), do: :disabled

  def open(%__MODULE__{} = state, receiver, connection_id)
      when is_pid(receiver) and is_binary(connection_id) do
    if String.trim(connection_id) == "" or byte_size(connection_id) > 128 do
      {:error, :invalid_connection_id}
    else
      {:ok,
       EgressHandoff.new(
         receiver,
         state.token,
         state.identity,
         state.configuration,
         connection_id,
         state.capacity,
         state.counters
       )}
    end
  end

  def open(%__MODULE__{}, _receiver, _connection_id), do: {:error, :invalid_connection_id}

  def readiness(%__MODULE__{} = state, %EgressHandoff{} = handoff, %Snapshot{} = policy) do
    if policy.effective.record_audio and EgressHandoff.issued_by?(handoff, self(), state) do
      binding =
        handoff
        |> EgressHandoff.recording_binding()
        |> Map.put(:policy_interval, Snapshot.interval(policy, :recording))

      status = if EgressHandoff.available?(handoff), do: :ready, else: :preparing
      {:ok, binding, status}
    else
      {:error, :unavailable}
    end
  end

  def readiness(_state, _handoff, _policy), do: {:error, :unavailable}

  def tap_readiness(%__MODULE__{} = state, %EgressHandoff{} = handoff) do
    if EgressHandoff.issued_by?(handoff, self(), state) do
      status = if EgressHandoff.available?(handoff), do: :ready, else: :preparing
      {:ok, EgressHandoff.recording_binding(handoff), status}
    else
      {:error, :unavailable}
    end
  end

  def tap_readiness(_state, _handoff), do: {:error, :unavailable}

  @spec install_policy(nil | t(), Snapshot.t()) :: {non_neg_integer(), nil | t()}
  def install_policy(nil, _snapshot), do: {0, nil}

  def install_policy(%__MODULE__{} = state, %Snapshot{} = snapshot) do
    revision = Snapshot.interval(snapshot, :recording)

    {dropped, buffer} =
      TimestampBuffer.retain(state.buffer, fn frame ->
        frame.policy_revision == revision and
          MapSet.member?(snapshot.present_participant_ids, frame.source_participant_id)
      end)

    :ok =
      EgressHandoff.install_policy(
        state.counters,
        revision,
        snapshot.effective.record_audio
      )

    {dropped, %{state | buffer: buffer}}
  end

  @spec put(t(), EgressHandoff.t(), NormalizedFrame.t(), Snapshot.t(), SubscriptionCatalog.t()) ::
          {:ok, t()} | {:error, term(), t()}
  def put(
        %__MODULE__{} = state,
        %EgressHandoff{} = handoff,
        %NormalizedFrame{} = frame,
        policy,
        subscriptions
      ) do
    with :ok <- validate_handoff(handoff, state),
         :ok <- validate_frame(frame, state, policy, subscriptions),
         :ok <- validate_sequence(frame, state),
         {:ok, buffer} <- TimestampBuffer.put(state.buffer, frame) do
      {:ok,
       %{
         state
         | buffer: buffer,
           source_sequences:
             Map.put(
               state.source_sequences,
               TimestampBuffer.source_key(frame),
               frame.sequence_number
             )
       }}
    else
      {:error, :buffer_full} ->
        {:error, :buffer_full, %{state | buffer_overflows: state.buffer_overflows + 1}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @spec take_through(nil | t(), non_neg_integer()) ::
          {:ok, [{non_neg_integer(), map()}], nil | t()} | {:error, term()}
  def take_through(nil, _timestamp), do: {:ok, [], nil}

  def take_through(%__MODULE__{} = state, timestamp) do
    case TimestampBuffer.take_through(state.buffer, timestamp) do
      {:ok, buckets, buffer} -> {:ok, buckets, %{state | buffer: buffer}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec stats(nil | t()) :: map()
  def stats(nil),
    do: %{buffered_timestamps: 0, buffer_overflows: 0, pending_frames: 0, rejected_frames: 0}

  def stats(%__MODULE__{} = state) do
    state.counters
    |> EgressHandoff.stats()
    |> Map.merge(%{
      buffered_timestamps: map_size(state.buffer.buckets),
      buffer_overflows: state.buffer_overflows
    })
  end

  defp validate_handoff(handoff, state) do
    if EgressHandoff.receiver(handoff) == self() and EgressHandoff.token(handoff) == state.token,
      do: :ok,
      else: {:error, :recording_not_authorized}
  end

  defp validate_frame(frame, state, policy, subscriptions) do
    cond do
      not same_identity?(frame, state.identity) ->
        {:error, :wrong_room}

      is_nil(policy) ->
        {:error, :policy_unavailable}

      frame.policy_revision != Snapshot.interval(policy, :recording) ->
        {:error, :stale_policy_revision}

      not policy.effective.record_audio ->
        {:error, :recording_denied}

      not MapSet.member?(policy.present_participant_ids, frame.source_participant_id) ->
        {:error, :source_not_present}

      SubscriptionCatalog.monitor_recipient?(subscriptions, frame.source_participant_id) ->
        {:error, :source_not_authorized}

      not valid_format?(frame, state.configuration) ->
        {:error, :invalid_pcm_frame}

      true ->
        :ok
    end
  end

  defp validate_sequence(frame, state) do
    case Map.get(state.source_sequences, TimestampBuffer.source_key(frame), -1) do
      previous when frame.sequence_number > previous -> :ok
      _previous -> {:error, :stale_sequence}
    end
  end

  defp valid_format?(frame, format) do
    frame.sample_rate == format.sample_rate and frame.channels == format.channels and
      is_integer(frame.sequence_number) and frame.sequence_number >= 0 and
      is_integer(frame.timestamp) and frame.timestamp >= 0 and is_binary(frame.payload) and
      byte_size(frame.payload) == format.frame_samples * format.channels * 2
  end

  defp same_identity?(frame, identity) do
    frame.tenant_id == identity.tenant_id and frame.room_id == identity.room_id and
      frame.incarnation_id == identity.incarnation_id
  end
end
