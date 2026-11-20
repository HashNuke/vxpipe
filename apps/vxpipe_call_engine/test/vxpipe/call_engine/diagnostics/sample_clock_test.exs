defmodule Vxpipe.CallEngine.Diagnostics.SampleClockTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Diagnostics.SampleClock

  test "maps a sample endpoint within received audio, not the later inference callback" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 512, 1, 100_000))
    assert {:ok, %{offset_us: 84_000, uncertainty_us: 1_000}} = SampleClock.at(clock, 256)
    assert {:ok, %{offset_us: 100_000}} = SampleClock.at(clock, 512)
    assert {:error, :unobserved_audio} = SampleClock.at(clock, 513)
  end

  test "a packet gap is explicit and cannot be filled by extrapolation" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 512, 1, 100_000))
    {:ok, clock, [:audio_gap]} = SampleClock.push(clock, frame(1_024, 512, 3, 164_000))
    assert {:error, :unobserved_audio} = SampleClock.at(clock, 768)
    assert {:ok, %{offset_us: 164_000}} = SampleClock.at(clock, 1_536)
  end

  test "receipt jitter is retained as mapping uncertainty" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 512, 1, 100_000))
    {:ok, clock, []} = SampleClock.push(clock, frame(512, 512, 2, 142_000))
    assert {:ok, %{offset_us: 142_000, uncertainty_us: 11_000}} = SampleClock.at(clock, 1_024)
  end

  test "duplicate, reordered and foreign-source frames never change continuity" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    packet = frame(0, 512, 1, 100_000)
    {:ok, clock, []} = SampleClock.push(clock, packet)
    assert {:ok, ^clock, []} = SampleClock.push(clock, packet)
    assert {:error, :out_of_order} = SampleClock.push(clock, %{packet | sequence: 0})

    assert {:error, :source_mismatch} =
             SampleClock.push(clock, %{packet | source_epoch: "source-2"})

    assert {:error, :conflicting_frame} =
             SampleClock.push(clock, %{packet | received_offset_us: 110_000})
  end

  test "retention is bounded and an expired acoustic position stays unavailable" do
    clock = SampleClock.new("clock-1", "source-1", 16_000, maximum_frames: 2)

    clock =
      Enum.reduce(0..2, clock, fn index, current ->
        {:ok, next, []} =
          SampleClock.push(current, frame(index * 512, 512, index + 1, 100_000 + index * 32_000))

        next
      end)

    assert SampleClock.retained_frames(clock) == 2
    assert {:error, :unobserved_audio} = SampleClock.at(clock, 256)
    assert {:ok, %{offset_us: 164_000}} = SampleClock.at(clock, 1_536)
  end

  test "timestamps before the run and invalid sample counts are not clamped" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    assert {:error, :invalid_frame} = SampleClock.push(clock, frame(0, 0, 1, 100_000))
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 512, 1, 10_000))
    assert {:error, :before_run} = SampleClock.at(clock, 0)
  end

  test "contiguous WebRTC frames compressed to 16ms retain monotone receipt estimates" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(149_358_612, 320, 279, 5_673_029))
    {:ok, clock, []} = SampleClock.push(clock, frame(149_358_932, 320, 280, 5_689_029))
    {:ok, clock, []} = SampleClock.push(clock, frame(149_359_252, 320, 281, 5_705_029))
    assert {:ok, %{offset_us: 5_673_029}} = SampleClock.at(clock, 149_358_932)

    assert {:ok, %{offset_us: 5_681_029, uncertainty_us: 5_000}} =
             SampleClock.at(clock, 149_359_092)

    assert {:ok, %{offset_us: 5_689_029}} = SampleClock.at(clock, 149_359_252)
    assert {:ok, %{offset_us: 5_689_079}} = SampleClock.at(clock, 149_359_253)
    assert {:ok, %{offset_us: 5_705_029}} = SampleClock.at(clock, 149_359_572)
  end

  test "equal-receipt batches collapse their interiors to receipt with duration uncertainty" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 320, 1, 100_000))
    {:ok, clock, []} = SampleClock.push(clock, frame(320, 320, 2, 100_000))

    for sample <- [321, 480, 640] do
      assert {:ok, %{offset_us: 100_000, uncertainty_us: 21_000}} = SampleClock.at(clock, sample)
    end

    assert {:ok, %{offset_us: 100_000, uncertainty_us: 1_000}} = SampleClock.at(clock, 320)
  end

  test "compression across missing audio remains unavailable" do
    clock = SampleClock.new("clock-1", "source-1", 16_000)
    {:ok, clock, []} = SampleClock.push(clock, frame(0, 320, 1, 100_000))
    {:ok, clock, [:audio_gap]} = SampleClock.push(clock, frame(640, 320, 3, 116_000))
    assert {:error, :unobserved_audio} = SampleClock.at(clock, 480)
    assert {:error, :clock_uncertain} = SampleClock.at(clock, 800)
    assert {:error, :clock_uncertain} = SampleClock.at(clock, 960)
  end

  defp frame(timestamp, count, sequence, received) do
    %{
      sample_timestamp: timestamp,
      sample_count: count,
      sequence: sequence,
      received_offset_us: received,
      source_epoch: "source-1"
    }
  end
end
