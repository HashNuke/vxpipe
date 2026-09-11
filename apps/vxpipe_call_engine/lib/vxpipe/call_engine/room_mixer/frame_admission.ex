defmodule Vxpipe.CallEngine.RoomMixer.FrameAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.NormalizedFrame
  alias Vxpipe.CallEngine.RoomMixer.{State, SubscriptionCatalog, TimestampBuffer}

  @spec put(State.t(), NormalizedFrame.t()) :: {:ok, State.t()} | {:error, term(), State.t()}
  def put(%State{} = state, %NormalizedFrame{} = frame) do
    with :ok <- validate_frame(frame, state),
         :ok <- validate_sequence(frame, state),
         {:ok, buffer} <- TimestampBuffer.put(state.buffer, frame) do
      {:ok,
       %{
         state
         | buffer: buffer,
           source_sequences:
             Map.put(state.source_sequences, frame.source_participant_id, frame.sequence_number)
       }}
    else
      {:error, :buffer_full} ->
        {:error, :buffer_full, %{state | buffer_overflows: state.buffer_overflows + 1}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp validate_frame(frame, state) do
    cond do
      not same_identity?(frame, state.identity) ->
        {:error, :wrong_room}

      is_nil(state.policy) ->
        {:error, :policy_unavailable}

      frame.policy_revision != state.policy.revision ->
        {:error, :stale_policy_revision}

      not MapSet.member?(state.policy.present_participant_ids, frame.source_participant_id) ->
        {:error, :source_not_present}

      SubscriptionCatalog.monitor_recipient?(
        state.subscriptions,
        frame.source_participant_id
      ) ->
        {:error, :source_not_authorized}

      not valid_format?(frame, state.format) ->
        {:error, :invalid_pcm_frame}

      true ->
        :ok
    end
  end

  defp validate_sequence(frame, state) do
    case Map.get(state.source_sequences, frame.source_participant_id, -1) do
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
