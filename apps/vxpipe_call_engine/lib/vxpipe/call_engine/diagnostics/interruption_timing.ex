defmodule Vxpipe.CallEngine.Diagnostics.InterruptionTiming do
  @moduledoc "Offers interrupted-output evidence to the interrupting human's source run."
  alias Vxpipe.CallEngine.Diagnostics.CaptureHandoff

  def observe(
        {%CaptureHandoff{} = handoff, generation, reference, turn, command},
        current,
        requested_at,
        result
      ) do
    request = current.request
    started_at = Map.get(current, :playback_started_at)

    stopped_at =
      case result do
        {:ok, _played_ms, received_at} -> received_at
        _ -> nil
      end

    reason =
      cond do
        started_at == nil -> :not_playing
        stopped_at == nil -> :stop_unavailable
        true -> nil
      end

    identity =
      {request.participant_id, request.source_participant_id, request.connection_id,
       request.correlation_id, request.command_id, request.output_id}

    _ =
      CaptureHandoff.offer(
        handoff,
        {:barge_in_playback, generation, reference, turn, command, identity, started_at,
         requested_at, stopped_at, reason}
      )

    :ok
  end

  def observe(_, _, _, _), do: :ok
end
