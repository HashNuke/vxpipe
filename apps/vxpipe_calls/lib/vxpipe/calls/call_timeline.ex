defmodule Vxpipe.Calls.CallTimeline do
  @moduledoc "Builds an ordered inspection timeline from permitted persisted history."

  alias Vxpipe.Calls.{CallFact, CallTimelineEntry, VariableSnapshot}

  @tool_terminal_kinds [
    :tool_call_completed,
    :tool_call_failed,
    :tool_call_cancelled
  ]

  @spec project([CallFact.t()], [VariableSnapshot.t()]) :: [CallTimelineEntry.t()]
  def project(facts, snapshots) when is_list(facts) and is_list(snapshots) do
    tool_starts = tool_starts(facts)

    fact_entries =
      Enum.map(facts, fn fact ->
        CallTimelineEntry.from_fact(fact, observed_interval(fact, tool_starts))
      end)

    snapshot_entries = Enum.map(snapshots, &CallTimelineEntry.from_variable_snapshot/1)

    Enum.sort_by(fact_entries ++ snapshot_entries, &sort_key/1)
  end

  defp tool_starts(facts) do
    Map.new(
      Enum.flat_map(facts, fn
        %CallFact{kind: :tool_call_started, tool_call_id: tool_call_id} = fact
        when is_binary(tool_call_id) ->
          [{tool_call_id, fact}]

        _fact ->
          []
      end)
    )
  end

  defp observed_interval(
         %CallFact{kind: kind, tool_call_id: tool_call_id} = terminal,
         tool_starts
       )
       when kind in @tool_terminal_kinds and is_binary(tool_call_id) do
    case Map.fetch(tool_starts, tool_call_id) do
      {:ok, started} -> duration_options(started, terminal)
      :error -> []
    end
  end

  defp observed_interval(_fact, _tool_starts), do: []

  defp duration_options(started, terminal) do
    duration_microseconds = DateTime.diff(terminal.occurred_at, started.occurred_at, :microsecond)

    if duration_microseconds >= 0 do
      [
        observed_duration_ms: div(duration_microseconds, 1_000),
        duration_basis: :source_timestamps
      ]
    else
      []
    end
  end

  defp sort_key(entry) do
    source_rank = if is_integer(entry.source_sequence), do: 0, else: 1
    {entry.occurred_at, source_rank, entry.source_sequence || 0, entry.id}
  end
end
