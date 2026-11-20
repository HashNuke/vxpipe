defmodule Vxpipe.CallEngine.Diagnostics.LiveReportTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.LiveReport

  setup do
    generation = make_ref()
    turn = make_ref()
    context = %{generation: generation, clock_id: "clock", origin_us: -100_000}

    {:ok, state} =
      LiveReport.observe(LiveReport.new(context), {:provider_sample_mapping, generation, 0, 0})

    %{state: state, generation: generation, turn: turn}
  end

  test "interrupted playback remains pending without inventing a completed human turn", c do
    identity = {"agent", "other-human", "other-connection", "old-turn", "old-command", "output"}

    packet =
      {:barge_in_playback, c.generation, c.turn, "new-turn", "new-command", identity, -95_000,
       -80_000, -75_000, nil}

    assert {:ok, pending} = LiveReport.observe(c.state, packet)
    assert LiveReport.reports(pending) == []
    assert {:ok, ^pending} = LiveReport.observe(pending, packet)

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(pending, put_elem(packet, 8, -74_000))

    assert {:error, :foreign_generation} =
             LiveReport.observe(c.state, put_elem(packet, 1, make_ref()))
  end

  for order <- [:playback_first, :completion_first] do
    @tag order: order
    test "rejects contradictory canonical identity in either arrival order: #{order}", %{
      order: order
    } do
      generation = make_ref()
      reference = make_ref()
      state = LiveReport.new(%{generation: generation, clock_id: "clock", origin_us: -100_000})
      output = {"agent", "old-human", "old-connection", "old-turn", "old-command", "output"}

      playback =
        {:barge_in_playback, generation, reference, "new-turn", "new-command", output, -95_000,
         -80_000, -75_000, nil}

      valid_completion =
        {:room_turn_completed, generation, reference, "new-turn", "new-command", -70_000}

      invalid_completion =
        {:room_turn_completed, generation, reference, "different-turn", "different-command",
         -70_000}

      assert {:ok, valid} = LiveReport.observe(state, playback)
      assert {:ok, _} = LiveReport.observe(valid, valid_completion)

      [first, second] =
        if order == :playback_first,
          do: [playback, invalid_completion],
          else: [invalid_completion, playback]

      assert {:ok, pending} = LiveReport.observe(state, first)
      assert {:error, :conflicting_evidence} = LiveReport.observe(pending, second)
    end
  end

  test "accepted input start retains incomplete barge-in evidence before completion", c do
    packet =
      {:barge_in_playback, c.generation, c.turn, "new-turn", "new-command",
       {"agent", "old-human", "old-connection", "old-turn", "old-command", "output"}, -90_000,
       -70_000, -65_000, nil}

    state =
      observe(c.state, [
        packet,
        {:room_turn_started, c.generation, c.turn, "new-turn", "new-command", -60_000}
      ])

    [pending] = LiveReport.reports(state)
    assert pending.turn_id == "new-turn"
    assert pending.landmarks_us[:room_turn_completed] == nil
    assert [%{duration_us: nil}] = pending.barge_in.entries
    assert LiveReport.counts(state).observed_turns == 1

    next =
      observe(state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -40_000, 960},
        {:room_turn_completed, c.generation, c.turn, "new-turn", "new-command", -39_000}
      ])

    assert [%{turn_id: "new-turn", revision: revision}] = LiveReport.reports(next)
    assert revision > pending.revision
    assert LiveReport.counts(next).observed_turns == 1
  end

  test "overlapping canonical intervals cannot each claim the same onset" do
    g = make_ref()
    r = make_ref()
    other = make_ref()
    identity = {"agent", "human", "connection", "old-turn", "old-command", "output"}

    state =
      observe(LiveReport.new(%{generation: g, clock_id: "clock", origin_us: -100_000}), [
        {:provider_sample_mapping, g, 0, 0},
        {:acoustic_boundary, 0, :speech_started, 320, 20_000, 40_000, 100, nil},
        {:acoustic_boundary, 0, :speech_ended, 480, 30_000, 41_000, 100, nil},
        {:acoustic_progress, 0, 0, 1024},
        {:barge_in_playback, g, r, "turn", "command", identity, -90_000, -70_000, -65_000, nil},
        {:barge_in_playback, g, other, "other-turn", "other-command", identity, -90_000, -70_000,
         -65_000, nil},
        {:provider_landmark, g, r, :provider_end_evidence, -40_000, 960},
        {:provider_landmark, g, other, :provider_end_evidence, -39_000, 960},
        {:room_turn_completed, g, r, "turn", "command", -38_000},
        {:room_turn_completed, g, other, "other-turn", "other-command", -37_000}
      ])

    assert %{entries: [%{reasons: reasons}]} = LiveReport.unattached_segments(state)
    assert :ambiguous_boundary in reasons
    reports = LiveReport.reports(state)
    assert length(reports) == 2

    assert Enum.all?(reports, fn report ->
             [%{duration_us: duration}] = report.barge_in.entries
             duration == nil
           end)
  end

  for order <- [:start_first, :redirect_first] do
    @tag order: order
    test "accepted start fences conflicting canonical redirects: #{order}", c do
      started = {:room_turn_started, c.generation, c.turn, "turn", "command", -60_000}
      redirect = {:turn_link, c.generation, c.turn, c.generation, make_ref()}

      [first, second] =
        if c.order == :start_first, do: [started, redirect], else: [redirect, started]

      assert {:ok, state} = LiveReport.observe(c.state, first)
      assert {:error, :conflicting_evidence} = LiveReport.observe(state, second)
    end
  end

  test "late onset revises the same human report with barge-in stop delay", c do
    packet =
      {:barge_in_playback, c.generation, c.turn, "new-turn", "new-command",
       {"agent", "old-human", "old-connection", "old-turn", "old-command", "output"}, -90_000,
       -70_000, -65_000, nil}

    state =
      observe(c.state, [
        packet,
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -40_000, 960},
        {:room_turn_completed, c.generation, c.turn, "new-turn", "new-command", -39_000}
      ])

    [pending] = LiveReport.reports(state)
    assert [%{duration_us: nil, reasons: [:missing_evidence]}] = pending.barge_in.entries

    state =
      observe(state, [{:acoustic_boundary, 0, :speech_started, 320, 20_000, 40_000, 100, nil}])

    [available] = LiveReport.reports(state)
    assert available.turn_id == pending.turn_id
    assert available.revision > pending.revision
    assert [%{duration_us: 15_000, response_turn_id: "old-turn"}] = available.barge_in.entries
    assert available.landmarks_us[:first_audio_started] == nil
  end

  test "retains multiple acoustic segments per canonical turn and unattached speech", c do
    boundaries = [
      {:acoustic_boundary, 0, :speech_started, 0, 0, 1_000, 100, nil},
      {:acoustic_boundary, 0, :speech_ended, 160, 10_000, 11_000, 100, nil},
      {:acoustic_boundary, 0, :speech_started, 320, 20_000, 21_000, 100, nil},
      {:acoustic_boundary, 0, :speech_ended, 480, 30_000, 31_000, 100, nil},
      {:acoustic_boundary, 0, :speech_started, 800, 50_000, 51_000, 100, nil},
      {:acoustic_boundary, 0, :speech_ended, 960, 60_000, 61_000, 100, nil}
    ]

    state = observe(c.state, boundaries ++ [{:acoustic_progress, 0, 0, 1_024}])
    assert %{entries: [_, _, _], omitted_count: 0} = LiveReport.unattached_segments(state)
    assert LiveReport.reports(state) == []

    state =
      observe(state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000}
      ])

    [report] = LiveReport.reports(state)

    assert %{version: 1, entries: [first, second], omitted_count: 0, reasons: []} =
             report.acoustic_segments

    assert {first.start_sample, first.end_sample, first.start_us, first.end_us} ==
             {0, 160, 0, 10_000}

    assert {second.start_confirmed_us, second.end_confirmed_us} == {21_000, 31_000}

    assert %{entries: [%{start_sample: 800, end_sample: 960}]} =
             LiveReport.unattached_segments(state)

    assert LiveReport.reports(observe(state, boundaries)) == [report]
  end

  test "unattached segment retention reports omissions without inventing turns", c do
    packets =
      for n <- 0..32, kind <- [:speech_started, :speech_ended] do
        sample = 320 * n + if(kind == :speech_ended, do: 160, else: 0)
        {:acoustic_boundary, 0, kind, sample, sample * 60, sample * 60 + 100, 10, nil}
      end

    state = observe(c.state, packets)

    assert %{entries: entries, omitted_count: 1, reasons: [:segment_limit]} =
             LiveReport.unattached_segments(state)

    assert length(entries) == 32
    assert LiveReport.counts(state).observed_turns == 0

    state =
      observe(state, [
        {:acoustic_progress, 0, 0, 11_000},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, 600_000, 11_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", 601_000}
      ])

    assert [
             %{
               acoustic_segments: %{
                 entries: ^entries,
                 omitted_count: 1,
                 reasons: [:segment_limit]
               }
             }
           ] =
             LiveReport.reports(state)

    assert %{entries: [], omitted_count: 0} = LiveReport.unattached_segments(state)
  end

  test "competing canonical intervals keep acoustic evidence explicitly ambiguous", c do
    other = make_ref()

    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 0, 100, 10, nil},
        {:acoustic_boundary, 0, :speech_ended, 160, 10_000, 11_000, 10, nil},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -80_000, 320},
        {:provider_landmark, c.generation, other, :provider_end_evidence, -79_000, 320},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -78_000},
        {:room_turn_completed, c.generation, other, "other", "other-command", -77_000}
      ])

    assert %{entries: [%{reasons: reasons}]} = LiveReport.unattached_segments(state)
    assert :ambiguous_boundary in reasons
    assert Enum.all?(LiveReport.reports(state), &(&1.acoustic_segments.entries == []))
  end

  test "missing source mapping never borrows acoustic segments by wall clock", c do
    state = LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000})

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 0, 100, 10, nil},
        {:acoustic_boundary, 0, :speech_ended, 160, 10_000, 11_000, 10, nil},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -80_000, 320},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -79_000}
      ])

    assert [%{acoustic_segments: %{entries: []}}] = LiveReport.reports(state)
    assert %{entries: [_]} = LiveReport.unattached_segments(state)
    mapped = observe(state, [{:provider_sample_mapping, c.generation, 0, 0}])
    assert [%{acoustic_segments: %{entries: [_]}}] = LiveReport.reports(mapped)
    assert %{entries: []} = LiveReport.unattached_segments(mapped)
  end

  test "absent acoustic evidence remains unavailable rather than observed empty", c do
    state =
      observe(c.state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -80_000, 320},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -79_000}
      ])

    assert LiveReport.unattached_segments(state) == nil
    assert [%{acoustic_segments: nil}] = LiveReport.reports(state)
    observed = observe(state, [{:acoustic_progress, 0, 0, 320}])
    assert %{entries: []} = LiveReport.unattached_segments(observed)
    assert [%{acoustic_segments: %{entries: []}}] = LiveReport.reports(observed)
  end

  test "partial finalized coverage cannot claim an observed empty turn", c do
    state =
      observe(c.state, [
        {:acoustic_progress, 0, 0, 512},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000}
      ])

    assert [%{acoustic_segments: %{entries: [], reasons: [:pending]}}] = LiveReport.reports(state)
    state = observe(state, [{:acoustic_progress, 0, 0, 1_024}])
    assert [%{acoustic_segments: %{entries: [], reasons: []}}] = LiveReport.reports(state)
  end

  test "closed insufficient coverage reports its loss instead of remaining pending", c do
    state =
      observe(c.state, [
        {:acoustic_progress, 0, 0, 512},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000},
        {:reset, 0, :audio_gap, -55_000}
      ])

    assert [%{acoustic_segments: %{entries: [], reasons: [:audio_gap]}}] =
             LiveReport.reports(state)
  end

  test "a closed preceding epoch does not mark the next pending interval lost", c do
    previous = make_ref()

    state =
      observe(c.state, [
        {:acoustic_progress, 0, 0, 320},
        {:provider_landmark, c.generation, previous, :provider_end_evidence, -80_000, 320},
        {:reset, 0, :audio_gap, -79_000},
        {:acoustic_progress, 1, 320, 512},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000}
      ])

    assert [%{acoustic_segments: %{reasons: [:pending]}}] = LiveReport.reports(state)
  end

  test "a second end without onset cannot replace an already paired endpoint", c do
    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 160, 10_000, 15_000, 100, nil},
        {:acoustic_boundary, 0, :speech_ended, 320, 20_000, 30_000, 100, nil},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000}
      ])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:acoustic_boundary, 0, :speech_ended, 1_200, 75_000, 90_000, 100, nil}
             )

    assert [%{acoustic_segments: %{entries: [%{end_sample: 320}]}}] = LiveReport.reports(state)
  end

  test "contradictory confirmation order cannot poison previously accepted evidence", c do
    state =
      observe(c.state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -60_000, 640},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -59_000},
        {:acoustic_boundary, 0, :speech_started, 0, 0, 200_000, 10, nil}
      ])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:acoustic_boundary, 0, :speech_ended, 512, 32_000, 100_000, 10, nil}
             )

    assert [%{landmarks_us: %{provider_end_received: 40_000}}] = LiveReport.reports(state)

    assert %{entries: [%{start_confirmed_us: 200_000, end_sample: nil}]} =
             LiveReport.unattached_segments(state)
  end

  test "reset opening an epoch does not close its later partial segment", c do
    state =
      observe(c.state, [
        {:reset, 1, :audio_gap, -99_000},
        {:acoustic_boundary, 1, :speech_started, 512, 32_000, 64_000, 10, nil}
      ])

    assert %{entries: [%{reasons: [:pending]}]} = LiveReport.unattached_segments(state)
  end

  test "same-epoch reuse reset closes a partial segment", c do
    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 0, 200_000, 10, nil},
        {:reset, 0, :audio_gap, 0}
      ])

    assert %{entries: [%{reasons: [:audio_gap]}]} = LiveReport.unattached_segments(state)

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(state, {:acoustic_progress, 0, 0, 512})
  end

  test "reset separates partial segments and retains missing endpoint evidence", c do
    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 0, 100, 10, nil},
        {:reset, 1, :audio_gap, -99_000},
        {:acoustic_boundary, 1, :speech_ended, 160, 10_000, 11_000, 10, nil}
      ])

    assert %{entries: [start, finish]} = LiveReport.unattached_segments(state)
    assert start.start_sample == 0
    assert start.end_sample == nil
    assert :audio_gap in start.reasons
    assert finish.start_sample == nil
    assert finish.end_sample == 160
    assert :partial_start in finish.reasons
  end

  test "joins provider, accepted room and response evidence by identity, with run offsets", c do
    packets = [
      {:provider_landmark, c.generation, c.turn, :provider_text_commit, -80_000, 1_000},
      {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
      {:provider_landmark, c.generation, c.turn, :adapter_end_emission, -69_000, 2_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000},
      {:response_landmark, "turn", "command", "text", :first_response_text, -60_000},
      {:response_landmark, "turn", "command", "audio", :first_audio_start, -50_000}
    ]

    state = observe(c.state, packets)
    [report] = LiveReport.reports(state)
    assert report.turn_id == "turn"
    assert report.landmarks_us.provider_end_received == 30_000
    assert report.durations_us.provider_to_room == 2_000
    assert report.durations_us.text_to_first_audio == 10_000
    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.provider_turn_id != nil
    assert report.stt_allocation_id != nil
  end

  test "late wrapper links join earlier evidence, while unrelated output is never borrowed", c do
    inner = make_ref()
    inner_turn = make_ref()

    packets = [
      {:provider_landmark, inner, inner_turn, :provider_end_evidence, -70_000, 2_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000},
      {:response_landmark, "turn", "other-command", "output", :first_response_text, -60_000}
    ]

    state = observe(c.state, packets)
    [before] = LiveReport.reports(state)
    refute Map.has_key?(before.landmarks_us, :provider_end_received)
    state = observe(state, [{:turn_link, inner, inner_turn, c.generation, c.turn}])
    [after_link] = LiveReport.reports(state)
    assert after_link.landmarks_us.provider_end_received == 30_000
    refute Map.has_key?(after_link.landmarks_us, :first_response_text)
    assert after_link.revision > before.revision
    assert LiveReport.reports(observe(state, packets)) == [after_link]
  end

  test "a late confirmed endpoint updates the same row, separating boundary and confirmation",
       c do
    state =
      observe(c.state, [
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
      ])

    [before] = LiveReport.reports(state)

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 90_000, 1_000, nil},
        {:acoustic_progress, 0, 0, 3_072}
      ])

    [report] = LiveReport.reports(state)
    assert report.turn_id == before.turn_id
    assert report.revision > before.revision
    assert report.durations_us.speech_end_to_provider_end == 30_000
    assert report.durations_us.observer_confirmation == 50_000
    assert report.acoustic_sample == 512
  end

  test "resumed speech and reset gaps invalidate acoustic estimates without losing provider stages",
       c do
    base = [
      {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
      {:acoustic_boundary, 0, :speech_ended, 512, 40_000, 50_000, 1_000, nil},
      {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
      {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
    ]

    state = observe(c.state, base)

    resumed =
      observe(state, [{:acoustic_boundary, 0, :speech_started, 1_024, 60_000, 65_000, 1_000, nil}])

    [report] = LiveReport.reports(resumed)
    assert report.acoustic_reason == :ambiguous_boundary
    assert report.durations_us.speech_end_to_provider_end == nil
    assert report.durations_us.provider_to_room == 1_000
    reset = observe(state, [{:reset, 1, :audio_gap, -45_000}])
    assert [%{acoustic_reason: :audio_gap}] = LiveReport.reports(reset)
  end

  test "capacity bounds retained evidence and rejects invalid or conflicting identities", c do
    limited =
      LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000},
        maximum_packets: 1
      )

    packet = {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
    state = observe(limited, [packet, packet])

    assert {:error, :full} =
             LiveReport.observe(
               state,
               {:response_landmark, "turn", "command", "out", :first_response_text, -60_000}
             )

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:room_turn_completed, c.generation, c.turn, "other", "command", -68_000}
             )

    assert {:error, :invalid_evidence} = LiveReport.observe(state, {:audio, "not timing"})

    assert {:error, :foreign_generation} =
             LiveReport.observe(
               c.state,
               {:room_turn_completed, make_ref(), c.turn, "turn", "command", -68_000}
             )

    bytes =
      LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000},
        maximum_bytes: 1
      )

    assert {:error, :full} = LiveReport.observe(bytes, packet)
  end

  test "an unaccepted earlier provider turn cannot donate its endpoint to a later room turn", c do
    earlier = make_ref()

    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, earlier, :provider_end_evidence, -70_000, 2_000},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -30_000, 3_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -29_000}
      ])

    assert [%{durations_us: %{speech_end_to_provider_end: nil}}] = LiveReport.reports(state)
  end

  test "two canonical turns cannot share an accepted room identity", c do
    state =
      observe(c.state, [{:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}])

    assert {:error, :conflicting_evidence} =
             LiveReport.observe(
               state,
               {:room_turn_completed, c.generation, make_ref(), "turn", "other", -60_000}
             )
  end

  test "provider turns with indistinguishable endpoints do not claim the same acoustic estimate",
       c do
    other = make_ref()

    state =
      observe(c.state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, other, :provider_end_evidence, -70_000, 2_000},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
      ])

    assert [
             %{
               acoustic_reason: :ambiguous_boundary,
               durations_us: %{speech_end_to_provider_end: nil}
             }
           ] = LiveReport.reports(state)
  end

  test "missing provider-to-source sample alignment never yields an available acoustic duration",
       c do
    state = LiveReport.new(%{generation: c.generation, clock_id: "clock", origin_us: -100_000})

    state =
      observe(state, [
        {:acoustic_boundary, 0, :speech_started, 0, 10_000, 12_000, 1_000, nil},
        {:acoustic_boundary, 0, :speech_ended, 512, 20_000, 25_000, 1_000, nil},
        {:provider_landmark, c.generation, c.turn, :provider_end_evidence, -70_000, 2_000},
        {:room_turn_completed, c.generation, c.turn, "turn", "command", -68_000}
      ])

    assert [
             %{
               acoustic_reason: :clock_uncertain,
               durations_us: %{speech_end_to_provider_end: nil}
             }
           ] = LiveReport.reports(state)
  end

  defp observe(state, packets) do
    Enum.reduce(packets, state, fn packet, state ->
      assert {:ok, next} = LiveReport.observe(state, packet)
      next
    end)
  end
end
