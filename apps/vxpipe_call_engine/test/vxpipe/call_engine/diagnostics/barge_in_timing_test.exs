defmodule Vxpipe.CallEngine.Diagnostics.BargeInTimingTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.BargeInTiming

  setup do
    generation = make_ref()
    reference = make_ref()
    canonical = {generation, reference, "new-turn", "new-command"}

    packet =
      {:barge_in_playback, generation, reference, "new-turn", "new-command",
       {"agent", "old-human", "old-connection", "old-turn", "old-command", "output"}, -90_000,
       -70_000, -65_000, nil}

    onset = {:acoustic_boundary, 0, :speech_started, 320, 20_000, 40_000, 100, nil}
    %{canonical: canonical, packet: packet, onset: onset}
  end

  test "open speech and late confirmation measure onset to acknowledged stop", c do
    [entry] = project(c, [c.onset]).entries
    assert entry.duration_us == 15_000
    assert entry.speech_started_us == 20_000
    assert entry.speech_start_confirmed_us == 40_000
    assert entry.playback_stopped_us == 35_000
    assert entry.boundary == :server_egress
    assert entry.reasons == []
    assert entry.response_source_participant_id == "old-human"
    assert entry.response_turn_id == "old-turn"
    assert entry.output_id == "output"
    later = put_elem(c.onset, 5, 60_000)
    assert [%{duration_us: 15_000}] = project(c, [later]).entries

    assert [%{duration_us: 25_000}] =
             project(%{c | packet: put_elem(c.packet, 8, -55_000)}, [later]).entries
  end

  test "missing and ambiguous onset evidence cannot create a duration", c do
    assert [%{duration_us: nil, reasons: [:missing_evidence]}] = project(c, []).entries
    other = {:acoustic_boundary, 0, :speech_started, 400, 25_000, 45_000, 100, nil}

    assert [%{duration_us: nil, reasons: [:ambiguous_boundary]}] =
             project(c, [c.onset, other]).entries

    assert [%{duration_us: nil, reasons: [:source_interval_unavailable]}] =
             project(c, [c.onset], {nil, nil}).entries

    assert [%{duration_us: nil, reasons: [:source_interval_unavailable]}] =
             project(c, [c.onset], {0, nil}).entries
  end

  test "onset outside this source interval or before playback is not borrowed", c do
    assert [%{duration_us: nil}] = project(c, [c.onset], {500, 900}).entries
    earlier = put_elem(c.onset, 4, 5_000)
    assert [%{duration_us: nil}] = project(c, [earlier]).entries

    assert nil ==
             BargeInTiming.build(
               [put_elem(c.packet, 1, make_ref()), c.onset],
               c.canonical,
               -100_000,
               {0, 960}
             )
  end

  test "unstarted output and failed stop remain unavailable", c do
    unstarted = c.packet |> put_elem(6, nil) |> put_elem(9, :not_playing)
    failed = c.packet |> put_elem(8, nil) |> put_elem(9, :stop_unavailable)

    assert [%{duration_us: nil, reasons: [:not_playing]}] =
             project(%{c | packet: unstarted}, [c.onset]).entries

    assert [%{duration_us: nil, reasons: [:stop_unavailable]}] =
             project(%{c | packet: failed}, [c.onset]).entries
  end

  test "uncertain clocks and inference resets cannot yield a measured stop delay", c do
    uncertain = c.onset |> put_elem(4, nil) |> put_elem(6, nil) |> put_elem(7, :clock_uncertain)
    assert [%{duration_us: nil, reasons: [:clock_uncertain]}] = project(c, [uncertain]).entries

    assert [%{duration_us: nil, reasons: [:inference_reset]}] =
             project(c, [c.onset, {:reset, 1, :inference_failed, -75_000}]).entries
  end

  defp project(c, evidence, bounds \\ {0, 960}),
    do: BargeInTiming.build([c.packet | evidence], c.canonical, -100_000, bounds)
end
