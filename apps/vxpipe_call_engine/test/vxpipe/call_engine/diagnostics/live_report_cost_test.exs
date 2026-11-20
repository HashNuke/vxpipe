defmodule Vxpipe.CallEngine.Diagnostics.LiveReportCostTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "progress beyond completed turns has bounded processing cost and preserves reports" do
    generation = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})

    state =
      Enum.reduce(1..16, state, fn index, state ->
        reference = make_ref()
        finish = index * 16_000

        Enum.reduce(
          [
            {:provider_sample_mapping, generation, 0, 0},
            {:provider_landmark, generation, reference, :provider_end_evidence, index * 1_000_000,
             finish},
            {:room_turn_completed, generation, reference, "turn-#{index}", "command-#{index}",
             index * 1_000_000 + 1_000}
          ],
          state,
          fn packet, state ->
            assert {:ok, state} = LiveReport.observe(state, packet)
            state
          end
        )
      end)

    assert {:ok, state} = LiveReport.observe(state, {:acoustic_progress, 0, 0, 256_000})
    expected = LiveReport.reports(state)
    assert length(expected) == 16
    {:reductions, before} = Process.info(self(), :reductions)

    state =
      Enum.reduce(1..100, state, fn frame, state ->
        assert {:ok, next} =
                 LiveReport.observe(state, {:acoustic_progress, 0, 0, 256_000 + frame * 512})

        next
      end)

    {:reductions, after_count} = Process.info(self(), :reductions)
    assert LiveReport.reports(state) == expected

    assert after_count - before < 500_000,
           "unchanged report progress consumed #{after_count - before} reductions"
  end
end
