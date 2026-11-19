defmodule Vxpipe.Calls.Diagnostics.CoverageTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.Diagnostics.Coverage
  alias Vxpipe.Calls.TestLatencyRecords
  @now ~U[2026-11-19 12:00:02Z]

  test "absence is not collected, never a zero-latency run" do
    assert %{status: :not_collected} = Coverage.describe(nil, 0, @now)
  end

  test "fresh running coverage reports pending summaries without claiming completeness" do
    run = %{
      TestLatencyRecords.run()
      | counts: %{observed_turns: 2, dropped_audio_frames: 0, unmatched_provider_events: 0}
    }

    assert %{status: :collecting, pending_turns: 1, observed_turns: 2, stored_turns: 1} =
             Coverage.describe(run, 1, @now)
  end

  test "expired heartbeat and future clocks are unconfirmed rather than gracefully closed" do
    run = TestLatencyRecords.run()

    assert %{status: :unconfirmed, reasons: [:stale_heartbeat]} =
             Coverage.describe(run, 0, DateTime.add(@now, 10, :second))

    assert %{status: :unconfirmed, reasons: [:clock_uncertain]} =
             Coverage.describe(run, 0, DateTime.add(run.anchor_utc, -1, :second))

    assert run.state == :running
  end

  test "closed capture window is complete only when all expected summaries are durable" do
    run = closed_run()
    assert %{status: :complete, reasons: [], pending_turns: 0} = Coverage.describe(run, 2, @now)

    assert %{status: :incomplete, reasons: [:storage_loss], pending_turns: 1} =
             Coverage.describe(run, 1, @now)

    assert %{status: :incomplete, reasons: [:counter_mismatch]} = Coverage.describe(run, 3, @now)
  end

  test "loss counters and explicit reasons remain visible even after a normal close" do
    run = %{
      closed_run()
      | reasons: [:audio_gap],
        counts: %{observed_turns: 2, dropped_audio_frames: 1, unmatched_provider_events: 1}
    }

    report = Coverage.describe(run, 2, @now)
    assert report.status == :incomplete
    assert :audio_gap in report.reasons
    assert :unmatched_provider_events in report.reasons
    assert report.dropped_audio_frames == 1
    assert report.unmatched_provider_events == 1
  end

  test "disabled and call-ended describe capture termination without inventing full-call coverage" do
    run = %{closed_run() | reasons: [:disabled, :call_ended]}

    assert %{status: :complete, reasons: [], termination_reasons: [:disabled, :call_ended]} =
             Coverage.describe(run, 2, @now)

    assert %{status: :incomplete} = Coverage.describe(%{run | state: :incomplete}, 2, @now)
  end

  defp closed_run do
    %{
      TestLatencyRecords.run()
      | state: :closed,
        heartbeat_at: @now,
        closed_at: @now,
        counts: %{observed_turns: 2, dropped_audio_frames: 0, unmatched_provider_events: 0}
    }
  end
end
