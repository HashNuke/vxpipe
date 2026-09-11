defmodule Vxpipe.CallEngine.Recording.EgressHandoff do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.{EgressAcceptedFrame, NormalizedFrame}

  @gate_index 1
  @pending_index 2
  @rejected_index 3
  @sequence_index 1
  @timestamp_index 2
  @track_id "agent-egress"

  @enforce_keys [
    :capacity,
    :clock,
    :clock_origin_ms,
    :connection_id,
    :counters,
    :cursor,
    :format,
    :gate,
    :identity,
    :receiver,
    :token
  ]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{}

  @doc false
  @spec new(pid(), reference(), map(), map(), String.t(), pos_integer(), reference()) :: t()
  def new(receiver, token, identity, configuration, connection_id, capacity, counters)
      when is_pid(receiver) and is_reference(token) and is_map(identity) and
             is_map(configuration) and is_binary(connection_id) and is_integer(capacity) and
             capacity > 0 and is_reference(counters) do
    cursor = :atomics.new(2, signed: true)
    :ok = :atomics.put(cursor, @timestamp_index, -configuration.frame_samples)

    %__MODULE__{
      capacity: capacity,
      clock: Map.fetch!(configuration, :clock),
      clock_origin_ms: Map.fetch!(configuration, :clock_origin_ms),
      connection_id: connection_id,
      counters: counters,
      cursor: cursor,
      format: Map.take(configuration, [:channels, :frame_samples, :sample_rate]),
      gate: Map.fetch!(configuration, :gate),
      identity: identity,
      receiver: receiver,
      token: token
    }
  end

  @spec offer(t(), EgressAcceptedFrame.t()) :: :ok | :ignored | {:error, term()}
  def offer(%__MODULE__{} = handoff, %EgressAcceptedFrame{} = frame) do
    with :ok <- validate(frame, handoff),
         {:record, revision} <- policy(handoff.gate),
         :ok <- reserve(handoff) do
      normalized = normalize(frame, revision, handoff)
      send(handoff.receiver, {:vxpipe_recording_egress, handoff, normalized})
      :ok
    else
      :ignore -> :ignored
      {:error, _reason} = error -> error
    end
  end

  @doc false
  @spec release(t()) :: :ok
  def release(%__MODULE__{} = handoff) do
    _pending = :atomics.sub_get(handoff.counters, @pending_index, 1)
    :ok
  end

  @doc false
  @spec token(t()) :: reference()
  def token(%__MODULE__{} = handoff), do: handoff.token

  @doc false
  @spec receiver(t()) :: pid()
  def receiver(%__MODULE__{} = handoff), do: handoff.receiver

  @doc false
  @spec new_counters() :: reference()
  def new_counters do
    :atomics.new(3, signed: true)
  end

  @doc false
  @spec install_policy(reference(), non_neg_integer(), boolean()) :: :ok
  def install_policy(counters, revision, record?)
      when is_reference(counters) and is_integer(revision) and revision >= 0 and
             is_boolean(record?) do
    encoded = revision * 2 + if(record?, do: 1, else: 0)
    :ok = :atomics.put(counters, @gate_index, encoded)
  end

  @doc false
  @spec stats(reference()) :: %{
          pending_frames: non_neg_integer(),
          rejected_frames: non_neg_integer()
        }
  def stats(counters) when is_reference(counters) do
    %{
      pending_frames: :atomics.get(counters, @pending_index),
      rejected_frames: :atomics.get(counters, @rejected_index)
    }
  end

  defp policy(gate) do
    encoded = :atomics.get(gate, @gate_index)
    revision = div(encoded, 2)

    if rem(encoded, 2) == 1, do: {:record, revision}, else: :ignore
  end

  defp reserve(handoff) do
    pending = :atomics.get(handoff.counters, @pending_index)

    cond do
      pending >= handoff.capacity ->
        _rejected = :atomics.add_get(handoff.counters, @rejected_index, 1)
        {:error, :full}

      :atomics.compare_exchange(handoff.counters, @pending_index, pending, pending + 1) == :ok ->
        :ok

      true ->
        reserve(handoff)
    end
  end

  defp normalize(frame, revision, handoff) do
    %NormalizedFrame{
      tenant_id: frame.tenant_id,
      room_id: frame.room_id,
      incarnation_id: frame.incarnation_id,
      source_participant_id: frame.source_participant_id,
      connection_id: frame.connection_id,
      track_id: @track_id,
      sequence_number: next_sequence(handoff.cursor),
      timestamp: next_timestamp(handoff),
      policy_revision: revision,
      sample_rate: frame.sample_rate,
      channels: frame.channels,
      payload: frame.payload
    }
  end

  defp next_sequence(cursor), do: :atomics.add_get(cursor, @sequence_index, 1) - 1

  defp next_timestamp(handoff) do
    elapsed_ms = max(handoff.clock.() - handoff.clock_origin_ms, 0)
    elapsed_samples = div(elapsed_ms * handoff.format.sample_rate, 1_000)

    candidate =
      div(elapsed_samples, handoff.format.frame_samples) * handoff.format.frame_samples

    advance_timestamp(handoff.cursor, candidate, handoff.format.frame_samples)
  end

  defp advance_timestamp(cursor, candidate, frame_samples) do
    previous = :atomics.get(cursor, @timestamp_index)
    timestamp = max(candidate, previous + frame_samples)

    case :atomics.compare_exchange(cursor, @timestamp_index, previous, timestamp) do
      :ok -> timestamp
      _changed -> advance_timestamp(cursor, candidate, frame_samples)
    end
  end

  defp validate(frame, handoff) do
    cond do
      frame.tenant_id != handoff.identity.tenant_id ->
        {:error, :wrong_tenant}

      frame.room_id != handoff.identity.room_id ->
        {:error, :wrong_room}

      frame.incarnation_id != handoff.identity.incarnation_id ->
        {:error, :wrong_incarnation}

      frame.connection_id != handoff.connection_id ->
        {:error, :wrong_connection}

      not valid_identifier?(frame.source_participant_id) ->
        {:error, :invalid_source}

      frame.sample_rate != handoff.format.sample_rate ->
        {:error, :unsupported_audio}

      frame.channels != handoff.format.channels ->
        {:error, :unsupported_audio}

      not is_binary(frame.payload) ->
        {:error, :invalid_audio}

      byte_size(frame.payload) != handoff.format.frame_samples * handoff.format.channels * 2 ->
        {:error, :invalid_audio}

      true ->
        :ok
    end
  end

  defp valid_identifier?(value) do
    is_binary(value) and String.trim(value) != "" and byte_size(value) <= 128
  end
end
