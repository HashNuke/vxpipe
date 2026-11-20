defmodule Vxpipe.CallEngine.Diagnostics.LiveReportProgressEquivalenceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "mapped progress preserves full projection equivalence before, at and after coverage" do
    {state, mapping, packets} = fixture()
    state = observe(state, [mapping | packets])
    state = observe(state, [{:acoustic_progress, 0, 1_600, 2_000}])

    state =
      Enum.reduce([2_500, 3_199, 3_200, 3_201, 4_000], state, fn finalized, state ->
        next = observe(state, [{:acoustic_progress, 0, 1_600, finalized}])
        # An unchanged mapping must remain idempotent. It independently exercises
        # the complete projection path, without relying on a cached cursor update.
        assert observe(next, [mapping]) == next
        [report] = LiveReport.reports(next)

        if finalized < 3_200 do
          refute Map.has_key?(report.landmarks_us, :acoustic_end)
          assert :pending in report.acoustic_segments.reasons
        else
          assert report.landmarks_us.acoustic_end == 150_000
          assert report.acoustic_segments.reasons == []
        end

        next
      end)

    {projection, _} = LiveReport.project_segments(state, %{custom: {1_600, 4_000}})
    assert projection.custom.reasons == []

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:acoustic_progress, 0, 1_601, 4_100})
  end

  test "late mapping and boundaries rebuild evidence after cursor-only updates" do
    {state, mapping, packets} = fixture()
    state = observe(state, packets)
    state = observe(state, [{:acoustic_progress, 0, 1_600, 2_000}])
    state = observe(state, [{:acoustic_progress, 0, 1_600, 4_000}])
    [missing] = LiveReport.reports(state)
    refute Map.has_key?(missing.landmarks_us, :acoustic_end)

    state = observe(state, [mapping])
    [complete] = LiveReport.reports(state)
    assert complete.landmarks_us.acoustic_end == 150_000
    assert complete.revision > missing.revision

    late = {:acoustic_boundary, 0, :speech_started, 3_500, 218_750, 350_000, 1_000, nil}
    state = observe(state, [late])

    assert %{entries: [%{start_sample: 3_500, end_sample: nil}]} =
             LiveReport.unattached_segments(state)

    state = observe(state, [{:acoustic_progress, 0, 1_600, 4_500}])
    assert observe(state, [mapping]) == state
    assert observe(state, [late]) == state

    state = observe(state, [{:reset, 1, :audio_gap, 400_000}])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:acoustic_progress, 0, 1_600, 5_000})

    state = observe(state, [{:acoustic_progress, 1, 5_000, 5_512}])
    assert observe(state, [mapping]) == state
  end

  test "first progress establishes observed empty segment evidence" do
    generation = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})
    assert LiveReport.unattached_segments(state) == nil
    state = observe(state, [{:acoustic_progress, 0, 0, 512}])
    assert %{entries: [], omitted_count: 0, reasons: []} = LiveReport.unattached_segments(state)
  end

  defp fixture do
    generation = make_ref()
    reference = make_ref()
    state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: 0})
    mapping = {:provider_sample_mapping, generation, 320, 1_600}

    packets = [
      {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 120_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 2_400, 150_000, 200_000, 1_000, nil},
      {:provider_landmark, generation, reference, :provider_end_evidence, 300_000, 1_920},
      {:room_turn_completed, generation, reference, "turn", "command", 310_000}
    ]

    {state, mapping, packets}
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, state ->
      assert {:ok, next} = LiveReport.observe(state, packet)
      next
    end)
  end
end
