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

  defp settlements(index, rooms, inputs_per_room) do
    for frame <- 1..192,
        turn = DiagnosticsSchedule.turn_at(index, frame, rooms, inputs_per_room),
        not is_nil(turn),
        do: {frame, turn}
  end
end
