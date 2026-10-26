defmodule Vxpipe.CallEngine.Capability.SpeechToSpeech.Policy do
  @moduledoc "Policy transition, source-origin retirement, and output fencing for STS."

  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.{Hold, Input}
  alias Vxpipe.CallEngine.MediaPolicy.Snapshot

  import Vxpipe.CallEngine.Capability.SpeechToSpeech.Output,
    only: [
      retire_stale_pending: 1,
      audio_route_permitted?: 3,
      fence_output: 1,
      stop_unavailable: 2
    ]

  def apply_direct(%{descriptor: %{input_cutover: :close}} = state, _policy),
    do: Hold.close_for_cutover(state)

  def apply_direct(state, policy) do
    state = %{
      state
      | policy: policy,
        policy_revision: state.policy_revision + 1,
        origin_policy_revision: state.origin_policy_revision + 1
    }

    case retire_stale_pending(state) do
      {:ok, state} ->
        if audio_route_permitted?(state, state.human_id, state.agent_id) and
             audio_route_permitted?(state, state.agent_id, state.human_id) do
          {:reply, :ok, state}
        else
          {_played, state} = fence_output(state)
          {:reply, :ok, state}
        end

      {:error, _reason} ->
        stop_unavailable(:provider_failed, state)
    end
  end

  def apply(state, %Snapshot{} = snapshot) do
    case Input.apply_policy(state, snapshot) do
      {:ok, updated} ->
        updated =
          if agent_presence_changed?(
               state.input_policy,
               updated.input_policy,
               state.agent_id
             ) do
            %{updated | origin_policy_revision: updated.origin_policy_revision + 1}
          else
            updated
          end

        rotated? = Input.activity_origin_rotated?(state, updated)

        with :ok <- validate_cutover(state, updated),
             {:ok, updated} <- maybe_close_rotated_origin(updated, rotated?),
             {:ok, updated} <- retire_stale_pending(updated) do
          {_played, updated} =
            if rotated? or
                 not (audio_route_permitted?(updated, updated.human_id, updated.agent_id) and
                        audio_route_permitted?(updated, updated.agent_id, updated.human_id)),
               do: fence_output(updated),
               else: {0, updated}

          if rotated?,
            do:
              send(
                updated.owner,
                {:vxpipe_sts_activity_origin_changed, self(), snapshot.revision}
              )

          {:reply, :ok, updated}
        else
          {:error, :input_cutover} -> Hold.close_for_cutover(updated)
          {:error, _reason} -> stop_unavailable(:provider_failed, updated)
        end

      {:error, _reason} = error ->
        {:reply, error, state}
    end
  end

  defp maybe_close_rotated_origin(state, true), do: Input.close_rotated_origin(state)
  defp maybe_close_rotated_origin(state, false), do: {:ok, state}

  defp validate_cutover(%{descriptor: %{input_cutover: :close}} = before, updated) do
    if origin_changed?(before, updated), do: {:error, :input_cutover}, else: :ok
  end

  defp validate_cutover(_before, _updated), do: :ok

  defp origin_changed?(%{input_policy: %Snapshot{} = previous} = before, updated) do
    current = updated.input_policy

    Enum.any?([:audio_input, :audio_output, :speech_to_text], fn scope ->
      Snapshot.interval(previous, scope, before.human_id) !=
        Snapshot.interval(current, scope, before.human_id)
    end) or
      Enum.any?([before.human_id, before.agent_id], fn participant ->
        MapSet.member?(previous.present_participant_ids, participant) !=
          MapSet.member?(current.present_participant_ids, participant)
      end)
  end

  defp origin_changed?(before, _updated), do: is_reference(before.response_origins.current)

  defp agent_presence_changed?(%Snapshot{} = previous, %Snapshot{} = current, participant) do
    MapSet.member?(previous.present_participant_ids, participant) !=
      MapSet.member?(current.present_participant_ids, participant)
  end

  defp agent_presence_changed?(_previous, _current, _participant), do: false
end
