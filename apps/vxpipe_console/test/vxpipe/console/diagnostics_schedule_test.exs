defmodule Vxpipe.Console.DiagnosticsScheduleTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.DiagnosticsSchedule

  test "single input has fixed leading silence and two settlements" do
    assert settlements(0, 1, 1) == [{128, 1}, {192, 2}]
  end

  test "same-room humans are half a turn window apart across every supported topology" do
    for rooms <- 1..8 do
      for room <- 0..(rooms - 1) do
        [{first, 1}, {next_first, 2}] = settlements(room * 2, rooms, 2)
        [{second, 1}, {next_second, 2}] = settlements(room * 2 + 1, rooms, 2)
        assert second - first == 32
        assert next_first - first == 64
        assert next_second - second == 64
      end

      phases =
        for input <- 0..(rooms * 2 - 1) do
          [{first, 1}, _] = settlements(input, rooms, 2)
          first
        end

      assert length(Enum.uniq(phases)) == rooms * 2
    end
  end

  test "warm profile has exactly twenty measured seconds for every staggered input" do
    plan = DiagnosticsSchedule.profile(:warm)
    assert plan.duration_ns == 25_000_000_000
    assert plan.measurement_start_ns == 5_000_000_000
    assert plan.frames == 782

    for humans <- 1..2, rooms <- 1..div(16, humans), index <- 0..(rooms * humans - 1) do
      count = DiagnosticsSchedule.frame_count(index, rooms, humans, :warm)

      deadlines =
        for sequence <- 0..(count - 1),
            do: sequence * 32_000_000 + div(32_000_000 * index, rooms * humans)

      assert Enum.all?(deadlines, &(&1 < plan.duration_ns))
      assert Enum.count(deadlines, &(&1 >= plan.measurement_start_ns)) == 625

      turns =
        for frame <- 1..count,
            turn = DiagnosticsSchedule.turn_at(index, frame, rooms, humans, :warm),
            not is_nil(turn),
            do: {frame, turn}

      assert Enum.count(turns, fn {frame, _} ->
               Enum.at(deadlines, frame - 1) >= plan.measurement_start_ns
             end) >= 10

      assert Enum.map(turns, &elem(&1, 1)) == Enum.to_list(1..length(turns))
    end
  end

  test "actual measurement uses conservative VM-clock causal bounds" do
    window = DiagnosticsSchedule.measurement_window(10_000_000, 15_100_000, :warm)
    assert window == %{start_us: 15_100_000, end_us: 35_000_000, ready_by_us: 15_000_000}
    assert DiagnosticsSchedule.completed_within?(window, 15_100_000, 34_999_999)
    refute DiagnosticsSchedule.completed_within?(window, 15_099_999, 16_000_000)
    refute DiagnosticsSchedule.completed_within?(window, 16_000_000, 35_000_000)
    refute DiagnosticsSchedule.completed_within?(window, 17_000_000, 16_000_000)
  end

  defp settlements(index, rooms, inputs_per_room) do
    for frame <- 1..192,
        turn = DiagnosticsSchedule.turn_at(index, frame, rooms, inputs_per_room),
        not is_nil(turn),
        do: {frame, turn}
  end
end
