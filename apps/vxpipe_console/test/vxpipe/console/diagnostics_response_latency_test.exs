defmodule Vxpipe.Console.DiagnosticsResponseLatencyTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.{DiagnosticsResponseLatency, DiagnosticsSchedule}

  test "joins exact source and command identities and retains delayed measured turns" do
    {sources, turns, events} = fixture(2, 2, :warm)

    assert %{count: count, p95_us: 10} =
             DiagnosticsResponseLatency.summarize(sources, turns, events, 2, 2, :warm)

    assert count >= 40

    late =
      Enum.map(events, fn e ->
        if e.stage == :dispatched, do: %{e | at_us: e.at_us + 50_000_000}, else: e
      end)

    # One room's callbacks are ordered; moving every dispatch past later completions
    # is inconsistent evidence, rather than permission to remove delayed turns.
    assert_raise ArgumentError, fn ->
      DiagnosticsResponseLatency.summarize(sources, turns, late, 2, 2, :warm)
    end
  end

  test "missing, duplicate, cross-source and negative timings cannot disappear" do
    {sources, turns, events} = fixture(1, 1, :smoke)
    [first, second | rest] = events

    for bad <- [
          tl(events),
          [first | events],
          [%{first | connection_id: "other"}, second | rest],
          [first, %{second | command_id: "other"} | rest],
          [first, %{second | at_us: first.at_us - 1} | rest]
        ] do
      assert_raise ArgumentError, fn ->
        DiagnosticsResponseLatency.summarize(sources, turns, bad, 1, 1, :smoke)
      end
    end
  end

  test "late final dispatch stays in the nearest-rank population" do
    {sources, turns, events} = fixture(1, 1, :warm)
    final = List.last(events)
    late = List.replace_at(events, -1, %{final | at_us: final.at_us + 50_000_000})

    assert %{count: 10, p95_us: 50_000_010} =
             DiagnosticsResponseLatency.summarize(sources, turns, late, 1, 1, :warm)
  end

  test "canonical order cannot reclassify a slow measured turn as warm-up" do
    {sources, turns, events} = fixture(1, 1, :warm)
    final = List.last(events)
    events = List.replace_at(events, -1, %{final | at_us: final.at_us + 50_000_000})

    assert %{p95_us: 50_000_010} =
             DiagnosticsResponseLatency.summarize(sources, turns, events, 1, 1, :warm)

    rows = Map.fetch!(turns, 0)
    first = hd(rows)
    last = List.last(rows)
    keys = [:correlation_id, :command_id]

    swapped =
      rows
      |> List.replace_at(0, Map.merge(first, Map.take(last, keys)))
      |> List.replace_at(-1, Map.merge(last, Map.take(first, keys)))

    assert_raise ArgumentError, fn ->
      DiagnosticsResponseLatency.summarize(sources, %{0 => swapped}, events, 1, 1, :warm)
    end
  end

  defp fixture(rooms, humans, mode) do
    sources =
      Map.new(0..(rooms * humans - 1), fn i ->
        {i,
         %{
           room_id: "room-#{div(i, humans)}",
           incarnation_id: "incarnation-#{div(i, humans)}",
           participant_id: "human-#{i}",
           connection_id: "connection-#{i}"
         }}
      end)

    turns =
      Map.new(sources, fn {i, _} ->
        {i,
         for(
           {_frame, turn} <- DiagnosticsSchedule.settlements(i, rooms, humans, mode),
           do: %{
             turn: turn,
             correlation_id: "turn-#{i}-#{turn}",
             command_id: "command-#{i}-#{turn}"
           }
         )}
      end)

    events =
      for {i, rows} <- turns, row <- rows, stage <- [:completed, :dispatched] do
        source = Map.fetch!(sources, i)

        Map.merge(source, %{
          stage: stage,
          correlation_id: row.correlation_id,
          command_id: row.command_id,
          at_us:
            -1_000_000 + row.turn * 100_000 + i * 1_000 +
              if(stage == :dispatched, do: 10, else: 0)
        })
      end

    {sources, turns, Enum.sort_by(events, & &1.at_us)}
  end
end
