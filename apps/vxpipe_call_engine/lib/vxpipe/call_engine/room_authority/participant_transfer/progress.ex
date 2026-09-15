defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Progress do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Pending
  alias Vxpipe.CallEngine.RoomAuthority.State

  @phases [:preparing, :cue, :releasing, :recovering, :recovered, :completed, :failed]
  @blockers [
    :speech_to_text,
    :text_to_speech,
    :model_inference,
    :tools,
    :recording,
    :room_services,
    :media,
    :other
  ]

  def publish(%Pending{} = pending, phase, blockers, %State{} = state, cause \\ nil)
      when phase in @phases do
    timeout = state.participant_transfer_runtime.plan.transfer_policy.attempt_timeout_ms
    started_at = pending.deadline_ms - timeout

    progress = %{
      destination: pending.request.destination_definition_key,
      phase: phase,
      blockers: blockers |> Enum.filter(&(&1 in @blockers)) |> Enum.uniq() |> Enum.sort(),
      elapsed_ms: max(System.monotonic_time(:millisecond) - started_at, 0)
    }

    progress =
      if cause == nil, do: progress, else: Map.put(progress, :reason, public_reason(cause))

    Enum.each(state.connections, fn {id, connection} ->
      if id in [pending.request.connection_id, pending.destination_connection_id] or
           connection.transfer_attempt_id == pending.attempt_id do
        send(connection.pid, {:vxpipe_transfer_progress, pending.attempt_id, progress})
      end
    end)

    :ok
  end

  defp public_reason(:deadline_elapsed), do: :timeout
  defp public_reason(:destination_connection_unavailable), do: :destination_disconnected
  defp public_reason(:destination_speech_to_text_unavailable), do: :speech_to_text_unavailable
  defp public_reason(:destination_text_to_speech_unavailable), do: :text_to_speech_unavailable
  defp public_reason(:destination_media_unavailable), do: :media_unavailable
  defp public_reason(:source_authority_changed), do: :policy_changed
  defp public_reason(:preparation_process_down), do: :preparation_failed
  defp public_reason(_cause), do: :unavailable
end
