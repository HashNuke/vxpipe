defmodule Vxpipe.CallEngine.RoomMixer.RecordingEgress do
  @moduledoc """
  Bounded recording-egress admission and duplicate evidence for one room mixer.

  Admission rank (`connection_order`) is keyed by live recording credentials:
  the rank entry for a connection is removed when its last credential is
  detached/revoked, so a reused connection id re-admits as most recent and the
  registry stays bounded by live connections instead of historical unique ids.

  Duplicate evidence keeps an exact counter (`room_duplicate_frames` /
  `agent_duplicate_frames`) while `selected_connection_ids` is only a bounded
  sample (first 64 distinct duplicate choices, sorted for stats). The sample
  may omit ids under sustained duplication; the counters never do.
  """

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Recording.EgressHandoff
  alias Vxpipe.CallEngine.RoomMixer.{RecordingSelection, SubscriptionCatalog, TimestampBuffer}

  @maximum_selected_connections 64

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
  defstruct @enforce_keys ++
              [
                connection_order: %{},
                connection_seq: 0,
                room_duplicate_frames: 0,
                agent_duplicate_frames: 0,
                selected_connection_ids: MapSet.new(),
                live_handoffs: %{},
                bound_listeners: %{}
              ]

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

  @spec open(nil | t(), pid(), String.t(), nil | String.t()) ::
          :disabled | {:ok, EgressHandoff.t()} | {:error, term()}
  def open(nil, _receiver, _connection_id, _listener), do: :disabled

  def open(%__MODULE__{} = state, receiver, connection_id, listener)
      when is_pid(receiver) and is_binary(connection_id) do
    cond do
      String.trim(connection_id) == "" or byte_size(connection_id) > 128 ->
        {:error, :invalid_connection_id}

      not valid_listener?(listener) ->
        {:error, :invalid_listener}

      true ->
        {state, _order} = admit_connection(state, connection_id)
        state = maybe_bind_listener(state, connection_id, listener)

        handoff =
          EgressHandoff.new(
            receiver,
            state.token,
            state.identity,
            state.configuration,
            connection_id,
            state.capacity,
            state.counters
          )

        live_handoffs = Map.put(state.live_handoffs || %{}, EgressHandoff.id(handoff), handoff)
        {:ok, handoff, %{state | live_handoffs: live_handoffs}}
    end
  end

  def open(%__MODULE__{}, _receiver, _connection_id, _listener),
    do: {:error, :invalid_connection_id}

  @spec open(nil | t(), pid(), String.t()) ::
          :disabled | {:ok, EgressHandoff.t()} | {:error, term()}
  def open(nil, _receiver, _connection_id), do: :disabled

  def open(%__MODULE__{} = state, receiver, connection_id)
      when is_pid(receiver) and is_binary(connection_id),
      do: open(state, receiver, connection_id, nil)

  def open(%__MODULE__{}, _receiver, _connection_id), do: {:error, :invalid_connection_id}

  @spec revoke_connection(nil | t(), String.t()) :: nil | t()
  def revoke_connection(nil, _connection_id), do: nil

  def revoke_connection(%__MODULE__{} = state, connection_id) when is_binary(connection_id) do
    live = state.live_handoffs || %{}

    {revoked, live} =
      Enum.split_with(live, fn {_id, handoff} ->
        is_struct(handoff, EgressHandoff) and handoff.connection_id == connection_id
      end)

    Enum.each(revoked, fn {_id, handoff} -> :ok = EgressHandoff.invalidate(handoff) end)

    # Drop per-source sequence cursors for the detached connection so a
    # re-entry with the same connection id starts fresh. Stale credentials
    # stay rejected through the live-handoff check above, not through
    # sequence reuse.
    source_sequences =
      state.source_sequences
      |> Enum.reject(fn {{_source, conn, _track}, _seq} -> conn == connection_id end)
      |> Map.new()

    # Revocation drops the listener binding with the connection: a detached
    # listener must not retain a room-cue exception through re-entry. It also
    # drops the admission rank so a reused connection id re-admits as most
    # recent and the rank registry stays bounded by live connections.
    cleared = %{state | live_handoffs: Map.new(live), source_sequences: source_sequences}

    cleared = %{
      cleared
      | bound_listeners: Map.delete(cleared.bound_listeners || %{}, connection_id)
    }

    %{cleared | connection_order: Map.delete(cleared.connection_order || %{}, connection_id)}
  end

  @spec revoke_handoff(nil | t(), EgressHandoff.t()) :: nil | t()
  def revoke_handoff(nil, _handoff), do: nil

  def revoke_handoff(%__MODULE__{} = state, %EgressHandoff{} = handoff) do
    # Invalidate the stored credential (shares the same validity atomics as
    # the sink-held copy) and drop it from the live set. Other handoffs for
    # the same connection stay live, preserving eligible preparation bindings
    # when a promotion-time bind fails.
    case Map.get(state.live_handoffs || %{}, EgressHandoff.id(handoff)) do
      %EgressHandoff{} = live -> :ok = EgressHandoff.invalidate(live)
      _ -> :ok = EgressHandoff.invalidate(handoff)
    end

    live = Map.delete(state.live_handoffs || %{}, EgressHandoff.id(handoff))
    connection_id = handoff.connection_id

    last_for_connection? =
      not Enum.any?(Map.values(live), fn
        %EgressHandoff{connection_id: ^connection_id} -> true
        _ -> false
      end)

    bound_listeners =
      if last_for_connection?,
        do: Map.delete(state.bound_listeners || %{}, connection_id),
        else: state.bound_listeners || %{}

    connection_order =
      if last_for_connection?,
        do: Map.delete(state.connection_order || %{}, connection_id),
        else: state.connection_order || %{}

    %{
      state
      | live_handoffs: live,
        bound_listeners: bound_listeners,
        connection_order: connection_order
    }
  end

  def readiness(%__MODULE__{} = state, %EgressHandoff{} = handoff, %Snapshot{} = policy) do
    if policy.effective.record_audio and EgressHandoff.issued_by?(handoff, self(), state) and
         live_handoff?(state, handoff) do
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
    if EgressHandoff.issued_by?(handoff, self(), state) and live_handoff?(state, handoff) do
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
    bound = state.bound_listeners || %{}

    {dropped, buffer} =
      TimestampBuffer.retain(state.buffer, fn frame ->
        frame.policy_revision == revision and
          (MapSet.member?(snapshot.present_participant_ids, frame.source_participant_id) or
             room_bound_source?(bound, frame))
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
         :ok <- validate_sequence(frame, state) do
      {state, _order} = admit_connection(state, frame.connection_id)

      state = %{
        state
        | source_sequences:
            Map.put(
              state.source_sequences,
              TimestampBuffer.source_key(frame),
              frame.sequence_number
            )
      }

      case dedupe_put(state, frame) do
        {:duplicate, state} ->
          {:ok, state}

        {:insert, state} ->
          case TimestampBuffer.put(
                 state.buffer,
                 frame_with_evidence(frame, 0, nil, state.connection_order)
               ) do
            {:ok, buffer} ->
              {:ok, %{state | buffer: buffer}}

            {:error, :buffer_full} ->
              {:error, :buffer_full, %{state | buffer_overflows: state.buffer_overflows + 1}}

            {:error, reason} ->
              {:error, reason, state}
          end
      end
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
    do: %{
      buffered_timestamps: 0,
      buffer_overflows: 0,
      pending_frames: 0,
      rejected_frames: 0,
      room_duplicate_frames: 0,
      agent_duplicate_frames: 0,
      recording_duplicate_frames: 0,
      selected_connection_ids: []
    }

  def stats(%__MODULE__{} = state) do
    state.counters
    |> EgressHandoff.stats()
    |> Map.merge(%{
      buffered_timestamps: map_size(state.buffer.buckets),
      buffer_overflows: state.buffer_overflows,
      room_duplicate_frames: state.room_duplicate_frames,
      agent_duplicate_frames: state.agent_duplicate_frames,
      recording_duplicate_frames: state.room_duplicate_frames + state.agent_duplicate_frames,
      selected_connection_ids: state.selected_connection_ids |> MapSet.to_list() |> Enum.sort()
    })
  end

  # Bounded source deduplication shared by room-origin and agent-origin
  # accepted frames. Within one room-clock timestamp, frames sharing a
  # selection group (room together, otherwise per source) are reduced to one:
  # first accepted wins, except a different payload chooses the newest
  # admitted listener. Equivalent payloads preserve the first accepted frame
  # while tracking the highest admission rank seen for that payload, so a
  # later different payload is compared against the payload's best rank
  # instead of only the first frame's rank. Duplicates are counted and the
  # winning connection is recorded; PCM is never stored in metadata and no
  # per-timestamp history is kept beyond the bounded egress buffer.
  @spec dedupe_put(t(), NormalizedFrame.t()) :: {:duplicate, t()} | {:insert, t()}
  defp dedupe_put(%__MODULE__{} = state, %NormalizedFrame{} = frame) do
    bucket = Map.get(state.buffer.buckets, frame.timestamp, %{})
    group = RecordingSelection.group_key(frame)

    existing =
      Enum.find(bucket, fn {_key, other} ->
        RecordingSelection.group_key(other) == group
      end)

    case existing do
      nil ->
        {:insert, state}

      {existing_key, kept} ->
        case RecordingSelection.resolve(kept, frame, state.connection_order) do
          :distinct ->
            {:insert, state}

          {:keep_first, 1, selected} ->
            kept_duplicates = Map.get(kept, :recording_duplicate_frames, 0) + 1

            updated = %{
              kept
              | recording_duplicate_frames: kept_duplicates,
                recording_selected_connection_id: selected
            }

            updated =
              if kept.payload == frame.payload do
                RecordingSelection.track_equivalent(updated, frame, state.connection_order)
              else
                updated
              end

            buffer = %{
              state.buffer
              | buckets:
                  Map.put(
                    state.buffer.buckets,
                    frame.timestamp,
                    Map.put(bucket, existing_key, updated)
                  )
            }

            {:duplicate, count_duplicate(%{state | buffer: buffer}, frame, selected)}

          {:replace, 1, selected} ->
            kept_duplicates = Map.get(kept, :recording_duplicate_frames, 0) + 1

            incoming =
              frame_with_evidence(frame, kept_duplicates, selected, state.connection_order)

            pruned = Map.delete(bucket, existing_key)
            new_key = TimestampBuffer.source_key(incoming)

            buffer = %{
              state.buffer
              | buckets:
                  Map.put(
                    state.buffer.buckets,
                    frame.timestamp,
                    Map.put(pruned, new_key, incoming)
                  )
            }

            {:duplicate, count_duplicate(%{state | buffer: buffer}, frame, selected)}
        end
    end
  end

  defp frame_with_evidence(frame, duplicates, selected, connection_order) do
    selected = selected || frame.connection_id

    max_order =
      case Map.get(frame, :recording_equivalent_max_order) do
        nil ->
          Map.get(connection_order, frame.connection_id, 0)

        stored when is_integer(stored) ->
          max(stored, Map.get(connection_order, frame.connection_id, 0))
      end

    %{
      frame
      | recording_duplicate_frames: duplicates,
        recording_selected_connection_id: selected,
        recording_equivalent_max_order: max_order
    }
  end

  defp count_duplicate(state, frame, selected) do
    # Bounded 64-entry sample of duplicate choices. The exact duplicate
    # counters below always increment; only the sampled id set is capped,
    # keeping the first 64 distinct winners.
    selected_ids = state.selected_connection_ids

    selected_ids =
      cond do
        MapSet.member?(selected_ids, selected) ->
          selected_ids

        MapSet.size(selected_ids) < @maximum_selected_connections ->
          MapSet.put(selected_ids, selected)

        true ->
          selected_ids
      end

    case Map.get(frame, :origin, :participant) do
      :room ->
        %{
          state
          | room_duplicate_frames: state.room_duplicate_frames + 1,
            selected_connection_ids: selected_ids
        }

      _participant ->
        %{
          state
          | agent_duplicate_frames: state.agent_duplicate_frames + 1,
            selected_connection_ids: selected_ids
        }
    end
  end

  defp validate_handoff(handoff, state) do
    cond do
      EgressHandoff.receiver(handoff) != self() or EgressHandoff.token(handoff) != state.token ->
        {:error, :recording_not_authorized}

      not EgressHandoff.valid?(handoff) ->
        {:error, :recording_not_authorized}

      not live_handoff?(state, handoff) ->
        {:error, :recording_not_authorized}

      true ->
        :ok
    end
  end

  defp live_handoff?(state, handoff) do
    case state.live_handoffs do
      live when is_map(live) ->
        case Map.get(live, EgressHandoff.id(handoff)) do
          %EgressHandoff{connection_id: connection_id} ->
            connection_id == handoff.connection_id and EgressHandoff.valid?(handoff)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp admit_connection(
         %__MODULE__{connection_order: order, connection_seq: seq} = state,
         connection_id
       ) do
    case Map.fetch(order || %{}, connection_id) do
      {:ok, existing} ->
        {state, existing}

      :error ->
        {%{
           state
           | connection_order: Map.put(order || %{}, connection_id, seq),
             connection_seq: seq + 1
         }, seq}
    end
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

      not source_present?(policy, frame) and
          not permitted_room_source?(state, frame) ->
        {:error, :source_not_present}

      SubscriptionCatalog.monitor_recipient?(subscriptions, frame.source_participant_id) ->
        {:error, :source_not_authorized}

      not valid_format?(frame, state.configuration) ->
        {:error, :invalid_pcm_frame}

      true ->
        :ok
    end
  end

  defp valid_listener?(nil), do: true

  defp valid_listener?(listener) when is_binary(listener) do
    String.trim(listener) != "" and byte_size(listener) <= 128
  end

  defp valid_listener?(_listener), do: false

  defp maybe_bind_listener(%__MODULE__{} = state, _connection_id, nil), do: state

  defp maybe_bind_listener(%__MODULE__{} = state, connection_id, listener)
       when is_binary(listener) do
    bound = state.bound_listeners || %{}

    case Map.get(bound, connection_id) do
      ^listener -> state
      _ -> %{state | bound_listeners: Map.put(bound, connection_id, listener)}
    end
  end

  defp source_present?(policy, frame) do
    MapSet.member?(policy.present_participant_ids, frame.source_participant_id)
  end

  # A permitted transfer destination is not present until readiness completes,
  # but it already holds a valid handoff. Room-origin cues addressed to that
  # active bound listener are accepted so its private assets are captured
  # before promotion. Participant-origin frames keep the ordinary presence
  # requirement and unknown sources are never accepted.
  defp permitted_room_source?(%__MODULE__{} = state, frame) do
    Map.get(frame, :origin, :participant) == :room and
      room_bound_source?(state.bound_listeners || %{}, frame) and
      bound_connection_live?(state, frame.connection_id)
  end

  defp room_bound_source?(bound, frame) when is_map(bound) do
    source = Map.get(frame, :source_participant_id)
    connection = Map.get(frame, :connection_id)

    is_binary(source) and is_binary(connection) and Map.get(bound, connection) == source
  end

  defp room_bound_source?(_bound, _frame), do: false

  defp bound_connection_live?(%__MODULE__{} = state, connection_id)
       when is_binary(connection_id) do
    Enum.any?(Map.values(state.live_handoffs || %{}), fn
      %EgressHandoff{connection_id: ^connection_id} = handoff ->
        EgressHandoff.valid?(handoff)

      _ ->
        false
    end)
  end

  defp bound_connection_live?(_state, _connection_id), do: false

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
