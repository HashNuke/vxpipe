defmodule Vxpipe.Console.Test.DiagnosticsResponseLatency do
  @moduledoc "Complete canonical input to dispatch populations, independent of collection."
  alias Vxpipe.Console.Test.DiagnosticsSchedule
  @source_fields [:room_id, :incarnation_id, :participant_id, :connection_id]

  def summarize(sources, turns, events, rooms, humans, mode) do
    inputs = rooms * humans
    indices = Enum.to_list(0..(inputs - 1))
    ensure!(Enum.sort(Map.keys(sources)) == indices and Enum.sort(Map.keys(turns)) == indices)

    ensure!(
      sources |> Map.values() |> Enum.map(&source_key/1) |> Enum.uniq() |> length() == inputs
    )

    plan = DiagnosticsSchedule.profile(mode)

    expected =
      for index <- indices,
          {row, {frame, turn}} <- checked_turns(turns, index, rooms, humans, mode),
          into: %{} do
        source = Map.fetch!(sources, index)
        ensure!(row.turn == turn)
        key = turn_key(Map.merge(source, row))
        offset = (frame - 1) * 32_000_000 + div(32_000_000 * index, inputs)

        {key,
         %{
           input: index,
           turn: turn,
           measured?: offset >= plan.measurement_start_ns and offset < plan.duration_ns
         }}
      end

    ensure!(map_size(expected) == Enum.sum(Enum.map(turns, fn {_, rows} -> length(rows) end)))
    ensure!(length(events) == 2 * map_size(expected))

    {observed, _clocks, _ordinals} =
      Enum.reduce(events, {%{}, %{}, %{}}, fn event, {observed, clocks, ordinals} ->
        key = turn_key(event)
        room = {event.room_id, event.incarnation_id}
        ensure!(Map.has_key?(expected, key) and is_integer(event.at_us))
        ensure!(event.at_us >= Map.get(clocks, room, event.at_us))
        previous = Map.get(observed, key, %{})

        ensure!(
          event.stage in [:completed, :dispatched] and not Map.has_key?(previous, event.stage)
        )

        if event.stage == :dispatched, do: ensure!(Map.has_key?(previous, :completed))

        expected_turn = Map.fetch!(expected, key)

        ordinals =
          if event.stage == :completed do
            ensure!(expected_turn.turn == Map.get(ordinals, expected_turn.input, 1))
            Map.put(ordinals, expected_turn.input, expected_turn.turn + 1)
          else
            ordinals
          end

        {Map.put(observed, key, Map.put(previous, event.stage, event.at_us)),
         Map.put(clocks, room, event.at_us), ordinals}
      end)

    durations =
      Enum.flat_map(expected, fn {key, expected_turn} ->
        record = Map.get(observed, key, %{})
        ensure!(Map.has_key?(record, :completed) and Map.has_key?(record, :dispatched))
        if expected_turn.measured?, do: [record.dispatched - record.completed], else: []
      end)

    count = length(durations)
    ensure!(count > 0)
    %{count: count, p95_us: durations |> Enum.sort() |> Enum.at(div(95 * count + 99, 100) - 1)}
  end

  defp checked_turns(turns, index, rooms, humans, mode) do
    rows = Map.fetch!(turns, index)
    schedule = DiagnosticsSchedule.settlements(index, rooms, humans, mode)
    ensure!(length(rows) == length(schedule))
    Enum.zip(rows, schedule)
  end

  defp source_key(source), do: Enum.map(@source_fields, &Map.fetch!(source, &1))

  defp turn_key(record) do
    fields = source_key(record) ++ [record.correlation_id, record.command_id]
    ensure!(Enum.all?(fields, &(is_binary(&1) and &1 != "")))
    List.to_tuple(fields)
  end

  defp ensure!(true), do: :ok
  defp ensure!(_), do: raise(ArgumentError, "incomplete or conflicting response latency evidence")
end
