defmodule Vxpipe.Gateway.Telephony.Twilio.PCMU.RateConverter do
  @moduledoc false

  @factor 6
  @downsample_group_bytes @factor * 2

  @spec upsample_8_to_48(binary(), integer() | nil) ::
          {:ok, binary(), integer() | nil} | {:error, :invalid_linear_pcm}
  def upsample_8_to_48(pcm, previous)
      when is_binary(pcm) and rem(byte_size(pcm), 2) == 0 and
             (is_nil(previous) or
                (is_integer(previous) and previous >= -32_768 and previous <= 32_767)) do
    samples = for <<sample::little-signed-16 <- pcm>>, do: sample
    interpolate(samples, previous)
  end

  def upsample_8_to_48(_invalid, _previous), do: {:error, :invalid_linear_pcm}

  @spec downsample_48_to_8(binary(), binary()) ::
          {:ok, binary(), binary()} | {:error, :invalid_linear_pcm}
  def downsample_48_to_8(pcm, remainder)
      when is_binary(pcm) and is_binary(remainder) and rem(byte_size(pcm), 2) == 0 and
             rem(byte_size(remainder), 2) == 0 and byte_size(remainder) < @downsample_group_bytes do
    downsample_groups(remainder <> pcm, [])
  end

  def downsample_48_to_8(_invalid, _remainder), do: {:error, :invalid_linear_pcm}

  defp interpolate([], previous), do: {:ok, <<>>, previous}

  defp interpolate([first | _rest] = samples, nil), do: interpolate(samples, first)

  defp interpolate(samples, previous) do
    {output, last} =
      Enum.map_reduce(samples, previous, fn current, prior ->
        delta = current - prior

        interpolated =
          for phase <- 1..@factor, into: <<>> do
            <<prior + div(delta * phase, @factor)::little-signed-16>>
          end

        {interpolated, current}
      end)

    {:ok, IO.iodata_to_binary(output), last}
  end

  defp downsample_groups(
         <<a::little-signed-16, b::little-signed-16, c::little-signed-16, d::little-signed-16,
           e::little-signed-16, f::little-signed-16, rest::binary>>,
         output
       ) do
    average = div(a + b + c + d + e + f, @factor)
    downsample_groups(rest, [<<average::little-signed-16>> | output])
  end

  defp downsample_groups(remainder, output) do
    {:ok, output |> Enum.reverse() |> IO.iodata_to_binary(), remainder}
  end
end
