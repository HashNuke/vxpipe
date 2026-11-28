defmodule Vxpipe.CallEngine.Guardrails.Attempts do
  @moduledoc false

  # Each physical request produces a start and optionally a completion. Events
  # arrive newest-first so a completion supersedes that request's submission.
  def from_events(entry, selected_provider, ended_at) do
    entry.attempt_events
    |> Enum.uniq_by(& &1.ordinal)
    |> Enum.sort_by(& &1.ordinal)
    |> Enum.map(fn event ->
      start = wall_time(entry, event[:started_at_ms], entry.started_wall)
      finish = wall_time(entry, event[:ended_at_ms], ended_at)

      %{
        attempt_id: Map.fetch!(entry.attempt_ids, event.ordinal),
        ordinal: event.ordinal - 1,
        provider: event[:provider] || selected_provider,
        model: event[:model],
        request_id: event[:request_id],
        outcome: if(event.phase == :started, do: :cancelled, else: event.outcome),
        error_code: event[:error_code],
        started_at: start,
        ended_at: finish,
        duration_ms: event[:duration_ms] || max(0, DateTime.diff(finish, start, :millisecond)),
        retry_of: Map.get(entry.attempt_ids, event.ordinal - 1),
        usage: event[:usage] || :unknown
      }
    end)
  end

  defp wall_time(entry, milliseconds, _fallback) when is_integer(milliseconds),
    do: DateTime.add(entry.started_wall, milliseconds - entry.started_mono, :millisecond)

  defp wall_time(_entry, _milliseconds, fallback), do: fallback
end
