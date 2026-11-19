defmodule Vxpipe.CallEngine.Diagnostics.AudioTimelineTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.{AudioTimeline, CapturePacket}
  alias Vxpipe.CallEngine.Media.AudioFrame

  test "normalizes accepted PCM and maps samples to the run clock in microseconds" do
    frame = frame(48_000, 960)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, pcm, []} = AudioTimeline.push(timeline, frame)
    assert byte_size(pcm) == 640
    assert {:ok, position} = AudioTimeline.at(timeline, 320)
    assert position.offset_us == 20_000
    assert position.sample_rate == 16_000
    assert position.clock_id == "clock"
    assert {:ok, start} = AudioTimeline.at(timeline, 0)
    assert start.offset_us == 0
    assert start.uncertainty_us >= 1_000
  end

  test "duplicate bytes are not inferred again and conflicting duplicates fail" do
    frame = frame(16_000, 320)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, frame)
    assert {:duplicate, ^timeline} = AudioTimeline.push(timeline, frame)

    assert {:error, :conflicting_frame} =
             AudioTimeline.push(timeline, %{frame | payload: :binary.copy(<<2, 0>>, 320)})
  end

  test "source gaps cannot be hidden by rounding the normalized sample clock" do
    frame = frame(48_000, 960)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, frame)
    # One lost source sample need not make a full 16 kHz sample gap.
    next = %{frame | sequence_number: 2, timestamp: 961, received_at: -960}
    assert {:ok, timeline, _, [:audio_gap]} = AudioTimeline.push(timeline, next)
    assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 320)
  end

  test "decoded Opus requires verified PCM correspondence" do
    pcm = frame(48_000, 960)

    opus = %{
      pcm
      | codec: :opus,
        payload: <<1, 2, 3>>,
        activity_pcm: %{payload: pcm.payload, timestamp: 0, sample_rate: 48_000, channels: 1}
    }

    timeline = AudioTimeline.new("clock", "source", pcm.source_epoch, -1_000_000)
    assert {:ok, _, normalized, []} = AudioTimeline.push(timeline, opus)
    assert byte_size(normalized) == 640

    assert {:error, :unsupported_audio} =
             AudioTimeline.push(timeline, %{opus | activity_pcm: nil})

    invalid = %{opus | activity_pcm: %{opus.activity_pcm | timestamp: 1}}
    assert {:error, :unsupported_audio} = AudioTimeline.push(timeline, invalid)
  end

  test "capture retains only the bounded decoded Opus copy" do
    pcm = frame(48_000, 960)

    opus = %{
      pcm
      | codec: :opus,
        payload: <<1, 2, 3>>,
        activity_pcm: %{payload: pcm.payload, timestamp: 0, sample_rate: 48_000, channels: 1}
    }

    assert {:ok, _charge} = CapturePacket.charge({:audio, opus})
    assert {:audio, copied} = CapturePacket.copy({:audio, opus})
    assert copied.codec == :linear16
    assert copied.activity_pcm == nil
    assert copied.payload == pcm.payload

    for invalid <- [
          %{opus | activity_pcm: Map.put(opus.activity_pcm, :secret, "no")},
          %{opus | payload: :binary.copy(<<1>>, 131_072)},
          %{opus | activity_pcm: %{opus.activity_pcm | sample_rate: 16_000}}
        ] do
      assert {:error, :invalid_evidence} = CapturePacket.charge({:audio, invalid})
    end
  end

  test "source identity, sample rate and receipt clock cannot silently change" do
    frame = frame(16_000, 320)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, frame)
    next = %{frame | timestamp: 320, sequence_number: 2, received_at: -960}

    for replacement <- [
          %{next | source_epoch: make_ref()},
          %{next | participant_id: "other"},
          %{next | sample_rate: 8_000}
        ] do
      assert {:error, :source_mismatch} = AudioTimeline.push(timeline, replacement)
    end

    assert {:error, :out_of_order} = AudioTimeline.push(timeline, %{next | received_at: -990})
  end

  test "mapping retention is bounded and old samples become unavailable" do
    frame = frame(8_000, 160)

    timeline =
      AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000, maximum_frames: 2)

    timeline =
      Enum.reduce(0..4, timeline, fn index, timeline ->
        input = %{
          frame
          | timestamp: index * 160,
            sequence_number: index + 1,
            received_at: -980 + index * 20
        }

        assert {:ok, timeline, pcm, []} = AudioTimeline.push(timeline, input)
        assert byte_size(pcm) == 640
        timeline
      end)

    assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 320)
    assert {:ok, %{offset_us: 100_000}} = AudioTimeline.at(timeline, 1_600)
  end

  test "missing fields and oversized decoded audio are rejected without retaining input" do
    frame = frame(16_000, 320)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)

    assert {:error, :unsupported_audio} =
             AudioTimeline.push(timeline, Map.delete(frame, :source_epoch))

    assert {:error, :unsupported_audio} =
             AudioTimeline.push(timeline, %{frame | payload: :binary.copy(<<0>>, 131_074)})
  end

  test "a rounded source gap cannot give an old endpoint a new receipt time" do
    frame = frame(48_000, 959)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, frame)
    assert {:ok, %{offset_us: 20_000}} = AudioTimeline.at(timeline, 320)

    next = %{
      frame
      | timestamp: 960,
        payload: :binary.copy(<<1, 0>>, 960),
        sequence_number: 2,
        received_at: -940
    }

    assert {:ok, timeline, _, [:audio_gap]} = AudioTimeline.push(timeline, next)
    assert {:error, :unobserved_audio} = AudioTimeline.at(timeline, 320)
  end

  test "source receipt compression remains uncertain after gaps and normalization rounding" do
    frame = frame(48_000, 960)
    timeline = AudioTimeline.new("clock", "source", frame.source_epoch, -1_000_000)
    assert {:ok, timeline, _, []} = AudioTimeline.push(timeline, frame)

    for {samples, received} <- [{960, -975}, {961, -960}] do
      next = %{
        frame
        | timestamp: 961,
          sequence_number: 2,
          payload: :binary.copy(<<1, 0>>, samples),
          received_at: received
      }

      assert {:ok, next_timeline, _, [:audio_gap]} = AudioTimeline.push(timeline, next)
      assert {:error, :clock_uncertain} = AudioTimeline.at(next_timeline, 641)
    end
  end

  defp frame(rate, samples) do
    %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      codec: :linear16,
      sample_rate: rate,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      payload: :binary.copy(<<1, 0>>, samples),
      received_at: -980,
      source_epoch: make_ref()
    }
  end
end
