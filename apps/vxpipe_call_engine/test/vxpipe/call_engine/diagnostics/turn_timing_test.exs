defmodule Vxpipe.CallEngine.Diagnostics.TurnTimingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.TurnTiming

  test "backdated acoustic end is the baseline even when provider end precedes confirmation" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_800_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 1_500_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :observer_confirmed, 2_012_000, "clock-1")
    report = TurnTiming.report(timing)
    assert report.durations_us.speech_end_to_provider_end == 300_000
    assert report.durations_us.observer_confirmation == 512_000
    assert report.quality == :available
  end

  test "committed transcript segments never manufacture turn-end evidence" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_text_commit, 900_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_text_commit, 1_100_000, "clock-1")
    assert is_nil(TurnTiming.report(timing).durations_us.speech_end_to_provider_end)
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_400_000, "clock-1")
    assert TurnTiming.report(timing).durations_us.commit_to_provider_end == 300_000
    assert TurnTiming.report(timing).durations_us.speech_end_to_provider_end == 400_000
  end

  test "first text and audio stay first and retries cannot regress evidence" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :room_turn_completed, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :first_response_text, 1_650_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :first_response_text, 1_660_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :first_audio_started, 1_820_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :first_audio_started, 2_820_000, "clock-1")
    report = TurnTiming.report(timing)
    assert report.durations_us.room_to_first_text == 650_000
    assert report.durations_us.text_to_first_audio == 170_000
    assert is_nil(report.durations_us.speech_end_to_first_audio)
  end

  test "invalid order is unavailable rather than a clamped zero" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 2_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_000_000, "clock-1")
    report = TurnTiming.report(timing)
    assert is_nil(report.durations_us.speech_end_to_provider_end)
    assert report.metric_reasons.speech_end_to_provider_end == :invalid_order
    assert report.quality == :incomplete
  end

  test "cross-clock and unbounded input are rejected without changing the record" do
    timing = TurnTiming.new("clock-1")

    assert {:error, :clock_mismatch} =
             TurnTiming.observe(timing, :acoustic_end, 100, "clock-2")

    assert {:error, :invalid_observation} =
             TurnTiming.observe(timing, :unknown, 100, "clock-1")

    assert {:error, :invalid_observation} =
             TurnTiming.observe(timing, :acoustic_end, -1, "clock-1")

    assert TurnTiming.report(timing).landmarks_us == %{}
  end

  test "acoustic gaps invalidate acoustic durations but preserve independently measured response stages" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_400_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :room_turn_completed, 1_410_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :first_response_text, 2_000_000, "clock-1")
    {:ok, timing} = TurnTiming.invalidate_acoustic(timing, :audio_gap)
    report = TurnTiming.report(timing)
    assert is_nil(report.durations_us.speech_end_to_provider_end)
    assert report.metric_reasons.speech_end_to_provider_end == :audio_gap
    assert report.durations_us.room_to_first_text == 590_000
    assert report.durations_us.provider_to_room == 10_000
  end

  test "manual commit and silent responses retain honest partial measurements" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :manual_commit_sent, 1_500_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_700_000, "clock-1")
    report = TurnTiming.report(timing)
    assert report.durations_us.speech_end_to_manual_commit == 500_000
    assert report.durations_us.manual_commit_to_provider_end == 200_000
    assert is_nil(report.durations_us.room_to_first_text)
    assert is_nil(report.durations_us.text_to_first_audio)
  end
end
