defmodule Vxpipe.CallEngine.Media.PCMResampler do
  @moduledoc """
  Stateless linear-interpolation resampling of mono signed 16-bit little-endian PCM.

  Output sample positions derive from each frame's absolute input timestamp (in input
  samples), so consecutive frames tile exactly at any rate pair without carried state
  or drift. Integer arithmetic only; the last input sample of a frame is held for the
  final interpolation step instead of waiting for the next frame.
  """

  @doc """
  Resamples one frame. Returns the output payload and its timestamp in output samples.
  """
  @spec resample(binary(), non_neg_integer(), pos_integer(), pos_integer()) ::
          {binary(), non_neg_integer()}
  def resample(pcm, timestamp, rate, rate), do: {pcm, timestamp}

  def resample(<<>>, timestamp, from, to), do: {<<>>, ceil_div(timestamp * to, from)}

  def resample(pcm, timestamp, from, to)
      when is_binary(pcm) and is_integer(timestamp) and timestamp >= 0 and
             is_integer(from) and from > 0 and is_integer(to) and to > 0 do
    samples = List.to_tuple(for <<sample::little-signed-16 <- pcm>>, do: sample)
    count = tuple_size(samples)
    first = ceil_div(timestamp * to, from)
    last = ceil_div((timestamp + count) * to, from)

    payload =
      for output <- first..(last - 1)//1, into: <<>> do
        position = output * from
        index = div(position, to) - timestamp
        fraction = rem(position, to)
        current = elem(samples, index)
        next = elem(samples, min(index + 1, count - 1))
        <<current + div((next - current) * fraction, to)::little-signed-16>>
      end

    {payload, first}
  end

  defp ceil_div(numerator, denominator), do: div(numerator + denominator - 1, denominator)
end
