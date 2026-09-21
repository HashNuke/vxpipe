defmodule Vxpipe.Providers.Twilio.PCMU.RateConverterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Twilio.PCMU.RateConverter

  test "upsamples continuously across buffer boundaries" do
    assert {:ok, first, 6_000} =
             RateConverter.upsample_8_to_48(samples([0, 6_000]), nil)

    assert decoded(first) == [0, 0, 0, 0, 0, 0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000]

    assert {:ok, second, 12_000} =
             RateConverter.upsample_8_to_48(samples([12_000]), 6_000)

    assert decoded(second) == [7_000, 8_000, 9_000, 10_000, 11_000, 12_000]
  end

  test "downsamples complete six-sample groups and carries a partial group" do
    first = samples([0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000])
    assert {:ok, output, remainder} = RateConverter.downsample_48_to_8(first, <<>>)
    assert decoded(output) == [2_500]
    assert decoded(remainder) == [6_000, 7_000]

    second = samples([8_000, 9_000, 10_000, 11_000])
    assert {:ok, output, <<>>} = RateConverter.downsample_48_to_8(second, remainder)
    assert decoded(output) == [8_500]
  end

  test "rejects incomplete linear PCM samples" do
    assert {:error, :invalid_linear_pcm} = RateConverter.upsample_8_to_48(<<0>>, nil)
    assert {:error, :invalid_linear_pcm} = RateConverter.downsample_48_to_8(<<0>>, <<>>)
  end

  defp samples(values) do
    for value <- values, into: <<>>, do: <<value::little-signed-16>>
  end

  defp decoded(binary), do: for(<<value::little-signed-16 <- binary>>, do: value)
end
