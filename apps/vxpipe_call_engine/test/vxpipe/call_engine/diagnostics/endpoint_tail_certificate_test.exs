defmodule Vxpipe.CallEngine.Diagnostics.EndpointTailCertificateTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  test "explicit sub-window tail completes only the endpoint, not segment coverage" do
    {state, _, _} = base()
    [before] = LiveReport.reports(state)
    assert before.durations_us.speech_end_to_provider_end == nil
    certificate = {:endpoint_tail_certificate, 0, 0, 10_752, 11_200, 700_001}
    assert {:ok, next} = LiveReport.observe(state, certificate)
    [row] = LiveReport.reports(next)
    assert row.durations_us.speech_end_to_provider_end == 500_000
    assert row.acoustic_segments == before.acoustic_segments
    assert row.barge_in == before.barge_in
    assert next.packets[{:progress, 0}] == state.packets[{:progress, 0}]

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(next, {:acoustic_progress, 0, 0, 11_264})

    assert {:ok, closed} = LiveReport.observe(next, {:reset, 1, :provider_turn_settled, 700_002})
    assert {:ok, ^closed} = LiveReport.observe(closed, certificate)
    assert [%{durations_us: %{speech_end_to_provider_end: 500_000}}] = LiveReport.reports(closed)

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(closed, {:acoustic_progress, 0, 0, 11_264})
  end

  test "absent certificate and provider end beyond its exact accepted bound remain unavailable" do
    {state, _, _} = base()

    assert {:ok, next} =
             LiveReport.observe(
               state,
               {:endpoint_tail_certificate, 0, 0, 10_752, 11_199, 700_001}
             )

    assert [%{durations_us: %{speech_end_to_provider_end: nil}}] = LiveReport.reports(next)
  end

  test "late, wrong-origin, wrong-frontier, and full-window certificates cannot grant evidence" do
    {state, _, _} = base()

    for packet <- [
          {:endpoint_tail_certificate, 0, 1, 10_752, 11_200, 700_001},
          {:endpoint_tail_certificate, 0, 0, 10_753, 11_200, 700_001},
          {:endpoint_tail_certificate, 0, 0, 10_752, 11_264, 700_001},
          {:endpoint_tail_certificate, 1, 0, 10_752, 11_200, 700_001}
        ] do
      assert {:error, _} = LiveReport.observe(state, packet)
    end

    assert {:ok, closed} = LiveReport.observe(state, {:reset, 1, :provider_turn_settled, 700_002})

    assert {:error, _} =
             LiveReport.observe(
               closed,
               {:endpoint_tail_certificate, 0, 0, 10_752, 11_200, 700_001}
             )
  end

  test "a certificate cannot erase partial or genuine failure evidence" do
    for reason <- [:partial_start, :inference_failed, :audio_gap] do
      {state, _, _} = base()

      assert {:ok, state} =
               LiveReport.observe(
                 state,
                 {:endpoint_tail_certificate, 0, 0, 10_752, 11_200, 700_001}
               )

      assert {:ok, state} = LiveReport.observe(state, {:reset, 0, reason, 650_000})
      assert [%{durations_us: %{speech_end_to_provider_end: nil}}] = LiveReport.reports(state)
    end
  end

  test "certificate cannot classify an endpoint inside its unclassified tail" do
    {state, _, _} = base(10_880)

    assert {:ok, state} =
             LiveReport.observe(
               state,
               {:endpoint_tail_certificate, 0, 0, 10_752, 11_200, 700_001}
             )

    assert [%{durations_us: %{speech_end_to_provider_end: nil}}] = LiveReport.reports(state)
  end

  defp base(endpoint_sample \\ 3_200) do
    g = make_ref()
    t = make_ref()

    packets = [
      {:provider_sample_mapping, g, 0, 0},
      {:acoustic_boundary, 0, :speech_started, 1_600, 100_000, 150_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, endpoint_sample, 200_000, 300_000, 1_000, nil},
      {:acoustic_progress, 0, 0, 10_752},
      {:provider_landmark, g, t, :provider_end_evidence, 700_000, 11_200},
      {:room_turn_completed, g, t, "turn", "command", 710_000}
    ]

    state =
      Enum.reduce(
        packets,
        LiveReport.new(%{generation: g, clock_id: "clock", origin_us: 0}),
        fn packet, state ->
          assert {:ok, next} = LiveReport.observe(state, packet)
          next
        end
      )

    {state, g, t}
  end
end
