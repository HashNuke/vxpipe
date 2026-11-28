defmodule Vxpipe.CallEngine.Media.PCMResamplerTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Media.PCMResampler

  test "16 kHz frames preserve signed interpolation, absolute position and last-sample hold" do
    samples = [-32_768, 32_767, -10, -7, -12, 0]

    for count <- 0..length(samples), stamp <- [0, 1, 123_457], suffix <- [<<>>, <<255>>] do
      frame = Enum.take(samples, count)
      pcm = for value <- frame, into: <<>>, do: <<value::little-signed-16>>

      expected =
        for {left, right} <- Enum.zip(frame, Enum.drop(frame, 1) ++ Enum.take(frame, -1)),
            phase <- 0..2,
            into: <<>> do
          <<left + div((right - left) * phase, 3)::little-signed-16>>
        end

      assert PCMResampler.resample(pcm <> suffix, stamp, 16_000, 48_000) ==
               {expected, 3 * stamp}
    end
  end

  test "resampling a 20 ms STS output frame stays below the measured BEAM work budget" do
    pcm = :binary.copy(<<-1001::little-signed-16, 2002::little-signed-16>>, 160)
    PCMResampler.resample(pcm, 0, 16_000, 48_000)
    {:reductions, before_count} = Process.info(self(), :reductions)

    for _ <- 1..100 do
      PCMResampler.resample(pcm, 0, 16_000, 48_000)
    end

    {:reductions, after_count} = Process.info(self(), :reductions)
    assert div(after_count - before_count, 100) < 2_000
  end
end
