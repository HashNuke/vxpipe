defmodule Vxpipe.CallEngine.Diagnostics.AcousticObserverTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.AcousticObserver

  test "endpoint uses backdated samples while confirmation includes observer processing delay" do
    observer = AcousticObserver.new("clock", "source")

    {_observer, events} =
      feed(observer, Enum.concat(List.duplicate(0.9, 8), List.duplicate(0.1, 16)))

    assert {:speech_ended, endpoint} = List.last(events)
    assert endpoint.sample == 4_096
    assert endpoint.offset_us == 256_000
    assert endpoint.confirmed_offset_us == 1_068_000
    assert endpoint.uncertainty_us == 1_000
  end

  test "missing audio resets continuity rather than inventing an endpoint across the gap" do
    {observer, _events} = feed(AcousticObserver.new("clock", "source"), List.duplicate(0.9, 8))

    assert {:ok, observer, [], [:audio_gap]} =
             AcousticObserver.observe(observer, frame(9), 0.1, 620_000)

    {_observer, events} = feed(observer, List.duplicate(0.1, 16), 10)
    refute Enum.any?(events, &match?({:speech_ended, _}, &1))
  end

  test "retries do not advance inference windows and conflicting duplicates are rejected" do
    observer = AcousticObserver.new("clock", "source")
    assert {:ok, observer, [], []} = AcousticObserver.observe(observer, frame(0), 0.9, 40_000)
    assert {:ok, ^observer, [], []} = AcousticObserver.observe(observer, frame(0), 0.9, 50_000)

    assert {:error, :conflicting_frame} =
             AcousticObserver.observe(observer, frame(0), 0.1, 50_000)

    assert {:error, :source_mismatch} =
             AcousticObserver.observe(observer, %{frame(1) | source_epoch: "other"}, 0.9, 70_000)
  end

  test "expired mappings remain unavailable even when a boundary is detected" do
    observer = AcousticObserver.new("clock", "source", maximum_frames: 2)

    {_observer, events} =
      feed(observer, Enum.concat(List.duplicate(0.9, 8), List.duplicate(0.1, 16)))

    assert {:unmapped_boundary, :speech_ended, 4_096, :unobserved_audio} in events
  end

  defp feed(observer, probabilities, start \\ 0) do
    probabilities
    |> Enum.with_index(start)
    |> Enum.reduce({observer, []}, fn {probability, index}, {observer, events} ->
      assert {:ok, next, emitted, []} =
               AcousticObserver.observe(
                 observer,
                 frame(index),
                 probability,
                 (index + 1) * 32_000 + 300_000
               )

      {next, events ++ emitted}
    end)
  end

  defp frame(index),
    do: %{
      sample_timestamp: index * 512,
      sample_count: 512,
      sequence: index,
      received_offset_us: (index + 1) * 32_000,
      source_epoch: "source"
    }
end
