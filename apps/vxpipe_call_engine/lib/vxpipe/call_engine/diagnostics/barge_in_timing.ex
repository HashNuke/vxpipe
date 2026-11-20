defmodule Vxpipe.CallEngine.Diagnostics.BargeInTiming do
  @moduledoc "Joins source-owned acoustic onset to acknowledged interrupted server egress."
  @maximum 604_800_000_000
  @limit 32

  def build(packets, {generation, reference, turn, command}, origin, bounds, intervals \\ %{}) do
    interruptions =
      for {:barge_in_playback, ^generation, ^reference, ^turn, ^command, _, _, _, _, _} = packet <-
            packets,
          do: packet

    case interruptions do
      [] ->
        nil

      entries ->
        omitted = max(length(entries) - @limit, 0)
        entries = entries |> Enum.sort_by(&{elem(&1, 7), elem(&1, 5)}) |> Enum.take(@limit)

        %{
          version: 1,
          entries:
            Enum.map(
              entries,
              &entry(&1, packets, %{origin: origin, bounds: bounds, intervals: intervals})
            ),
          omitted_count: omitted,
          reasons: if(omitted > 0, do: [:entry_limit], else: [])
        }
    end
  end

  defp entry(
         {:barge_in_playback, _, _, _, _, identity, started, requested, stopped, reason},
         packets,
         %{origin: origin} = context
       ) do
    {agent, source, connection, turn, command, output} = identity

    entry = %{
      agent_participant_id: agent,
      response_source_participant_id: source,
      output_connection_id: connection,
      response_turn_id: turn,
      response_command_id: command,
      output_id: output,
      boundary: :server_egress,
      playback_started_us: offset(started, origin),
      interruption_requested_us: offset(requested, origin),
      playback_stopped_us: offset(stopped, origin),
      speech_started_us: nil,
      speech_start_confirmed_us: nil,
      speech_start_sample: nil,
      epoch: nil,
      uncertainty_us: nil,
      duration_us: nil,
      reasons: []
    }

    cond do
      reason != nil ->
        unavailable(entry, reason)

      Enum.any?(
        [entry.playback_started_us, entry.interruption_requested_us, entry.playback_stopped_us],
        &is_nil/1
      ) ->
        unavailable(entry, :before_run)

      true ->
        correlate(entry, packets, context)
    end
  end

  defp correlate(entry, packets, %{bounds: {first, last}} = context)
       when is_integer(first) and is_integer(last) do
    candidates =
      for {:acoustic_boundary, _, :speech_started, sample, at, _, _, _} = boundary <- packets,
          sample >= first and sample < last,
          at == nil or (at >= entry.playback_started_us and at <= entry.interruption_requested_us),
          do: boundary

    case candidates do
      [] -> unavailable(entry, :missing_evidence)
      [boundary] -> onset(entry, boundary, packets, context)
      _ -> unavailable(entry, :ambiguous_boundary)
    end
  end

  defp correlate(entry, _packets, _context),
    do: unavailable(entry, :source_interval_unavailable)

  defp onset(
         entry,
         {:acoustic_boundary, epoch, :speech_started, sample, at, confirmed, uncertainty, reason},
         packets,
         %{origin: origin, intervals: intervals}
       ) do
    entry = %{
      entry
      | epoch: epoch,
        speech_start_sample: sample,
        speech_started_us: at,
        speech_start_confirmed_us: confirmed,
        uncertainty_us: uncertainty
    }

    cond do
      ambiguous_owner?(intervals, sample) ->
        unavailable(entry, :ambiguous_boundary)

      reason != nil or at == nil or uncertainty == nil ->
        unavailable(entry, :clock_uncertain)

      reset_between?(packets, at + origin, entry.playback_stopped_us + origin) ->
        unavailable(entry, :inference_reset)

      true ->
        %{entry | duration_us: entry.playback_stopped_us - at}
    end
  end

  defp ambiguous_owner?(intervals, sample) do
    Enum.count(intervals, fn
      {_key, {first, last}} when is_integer(first) and is_integer(last) ->
        sample >= first and sample < last

      _ ->
        false
    end) > 1
  end

  defp reset_between?(packets, onset, stopped) do
    Enum.any?(packets, fn
      {:reset, _, reason, at} ->
        reason != :provider_turn_settled and at >= onset and at <= stopped

      _ ->
        false
    end)
  end

  defp unavailable(entry, reason), do: %{entry | duration_us: nil, reasons: [reason]}
  defp offset(nil, _origin), do: nil
  defp offset(at, origin) when at - origin >= 0 and at - origin <= @maximum, do: at - origin
  defp offset(_at, _origin), do: nil
end
