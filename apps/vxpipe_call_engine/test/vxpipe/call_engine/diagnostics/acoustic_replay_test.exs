defmodule Vxpipe.CallEngine.Diagnostics.AcousticReplayTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.Diagnostics.AcousticReplay
  alias Vxpipe.CallEngine.Speech.Silero

  test "retrying an identical PCM frame preserves the inference stream and report" do
    path =
      Path.expand(
        "../../../../../vxpipe_providers/test/fixtures/deepgram/short_answer_16k_mono_s16le.pcm",
        __DIR__
      )

    frames =
      for(<<chunk::binary-size(1_024) <- File.read!(path)>>, do: chunk)
      |> Enum.take(20)
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        %{
          pcm: chunk,
          sample_timestamp: index * 512,
          sample_count: 512,
          sequence: index,
          source_epoch: "fixture",
          received_offset_us: (index + 1) * 32_000,
          processed_offset_us: (index + 1) * 32_000 + 100_000
        }
      end)

    assert {:ok, model} = Silero.load()
    assert {:ok, original} = AcousticReplay.run(model, frames, "clock", "fixture")

    retried =
      Enum.flat_map(frames, fn frame ->
        if frame.sequence == 10, do: [frame, frame], else: [frame]
      end)

    assert {:ok, ^original} = AcousticReplay.run(model, retried, "clock", "fixture")
  end

  test "timestamped PCM runs through real Silero and retains discontinuity evidence" do
    path =
      Path.expand(
        "../../../../../vxpipe_providers/test/fixtures/deepgram/short_answer_16k_mono_s16le.pcm",
        __DIR__
      )

    pcm = File.read!(path)
    pcm = pcm <> :binary.copy(<<0>>, rem(1_024 - rem(byte_size(pcm), 1_024), 1_024) + 64 * 1_024)
    frames = for <<chunk::binary-size(1_024) <- pcm>>, do: chunk

    frames =
      frames
      |> Enum.with_index()
      |> Enum.map(fn {chunk, index} ->
        %{
          pcm: chunk,
          sample_timestamp: index * 512,
          sample_count: 512,
          sequence: index,
          source_epoch: "fixture",
          received_offset_us: (index + 1) * 32_000,
          processed_offset_us: (index + 1) * 32_000 + 100_000
        }
      end)

    assert {:ok, model} = Silero.load()
    assert {:ok, result} = AcousticReplay.run(model, frames, "clock", "fixture")
    assert result.frame_count == length(frames)
    assert result.notices == []
    assert Enum.any?(result.events, &match?({:speech_started, _}, &1))
    assert {:speech_ended, endpoint} = Enum.find(result.events, &match?({:speech_ended, _}, &1))
    assert endpoint.offset_us < endpoint.confirmed_offset_us
    refute inspect(result) =~ "pcm"

    assert {:ok, missing} =
             AcousticReplay.run(
               model,
               Enum.reject(frames, &(&1.sequence == 10)),
               "clock",
               "fixture"
             )

    assert :audio_gap in missing.notices
  end
end
