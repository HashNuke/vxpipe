defmodule Vxpipe.Gateway.Telephony.Twilio.PCMU.Codec do
  @moduledoc false

  import Bitwise

  @bias 0x84
  @clip 32_635

  @spec encode(binary()) :: {:ok, binary()} | {:error, :invalid_linear_pcm}
  def encode(pcm) when is_binary(pcm) and rem(byte_size(pcm), 2) == 0 do
    encoded = for <<sample::little-signed-16 <- pcm>>, into: <<>>, do: <<encode_sample(sample)>>
    {:ok, encoded}
  end

  def encode(_invalid), do: {:error, :invalid_linear_pcm}

  @spec decode(binary()) :: {:ok, binary()} | {:error, :invalid_pcmu}
  def decode(pcmu) when is_binary(pcmu) do
    decoded =
      for <<sample <- pcmu>>, into: <<>> do
        <<decode_sample(sample)::little-signed-16>>
      end

    {:ok, decoded}
  end

  def decode(_invalid), do: {:error, :invalid_pcmu}

  defp encode_sample(sample) do
    {magnitude, mask} =
      if sample < 0 do
        {min(-sample, @clip) + @bias, 0x7F}
      else
        {min(sample, @clip) + @bias, 0xFF}
      end

    exponent = exponent(magnitude)
    mantissa = band(magnitude >>> (exponent + 3), 0x0F)
    bxor(bor(exponent <<< 4, mantissa), mask)
  end

  defp decode_sample(sample) do
    inverted = bxor(sample, 0xFF)
    magnitude = (band(inverted, 0x0F) <<< 3) + @bias
    magnitude = magnitude <<< (band(inverted, 0x70) >>> 4)

    if band(inverted, 0x80) == 0 do
      magnitude - @bias
    else
      @bias - magnitude
    end
  end

  defp exponent(magnitude) when magnitude <= 0xFF, do: 0
  defp exponent(magnitude) when magnitude <= 0x1FF, do: 1
  defp exponent(magnitude) when magnitude <= 0x3FF, do: 2
  defp exponent(magnitude) when magnitude <= 0x7FF, do: 3
  defp exponent(magnitude) when magnitude <= 0xFFF, do: 4
  defp exponent(magnitude) when magnitude <= 0x1FFF, do: 5
  defp exponent(magnitude) when magnitude <= 0x3FFF, do: 6
  defp exponent(_magnitude), do: 7
end
