defmodule Vxpipe.CallEngine.Diagnostics.TimingFoundationsReviewTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.{SampleClock, TurnTiming}

  test "compressed frame arrival cannot produce a valid backwards sample clock" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 1, 100_000))
    {:ok, clock, _notices} = SampleClock.push(clock, frame(512, 2, 110_000))
    {:ok, previous} = SampleClock.at(clock, 512)

    assert {:ok, next} = SampleClock.at(clock, 513)
    assert next.offset_us >= previous.offset_us
    assert next.offset_us == 100_020
    assert next.uncertainty_us == 23_000
  end

  test "retention cannot silently remap an already observed shared frame boundary" do
    clock = SampleClock.new("clock-1", "source-1", 16_000, maximum_frames: 2)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 1, 100_000))
    {:ok, clock, []} = SampleClock.push(clock, frame(512, 2, 142_000))
    {:ok, before} = SampleClock.at(clock, 512)
    {:ok, clock, []} = SampleClock.push(clock, frame(1_024, 3, 174_000))

    case SampleClock.at(clock, 512) do
      {:error, :unobserved_audio} -> :ok
      {:ok, after_retention} -> assert after_retention.offset_us == before.offset_us
    end
  end

  test "a second acoustic segment cannot silently preserve the first segment latency" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :observer_confirmed, 1_512_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :acoustic_end, 2_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :observer_confirmed, 2_512_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 2_400_000, "clock-1")
    report = TurnTiming.report(timing)

    assert report.durations_us.speech_end_to_provider_end in [nil, 400_000]
  end

  test "room completion before adapter emission is inconsistent timing evidence" do
    timing = TurnTiming.new("clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :provider_end_received, 1_000_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :adapter_end_emitted, 1_200_000, "clock-1")
    {:ok, timing} = TurnTiming.observe(timing, :room_turn_completed, 1_100_000, "clock-1")
    report = TurnTiming.report(timing)

    assert is_nil(report.durations_us.provider_to_room)
    assert report.metric_reasons.provider_to_room == :invalid_order
  end

  test "bounded sample-clock storage rejects arbitrarily large integer frame identifiers" do
    clock = SampleClock.new("clock-1", "source-1", 16_000, maximum_frames: 1)
    oversized = Bitwise.bsl(1, 65_536)

    assert {:error, :invalid_frame} = SampleClock.push(clock, frame(oversized, 1, 100_000))
    assert {:error, :invalid_frame} = SampleClock.push(clock, frame(0, oversized, 100_000))
  end

  defp frame(timestamp, sequence, received) do
    %{
      sample_timestamp: timestamp,
      sample_count: 512,
      sequence: sequence,
      received_offset_us: received,
      source_epoch: "source-1"
    }
  end
end
