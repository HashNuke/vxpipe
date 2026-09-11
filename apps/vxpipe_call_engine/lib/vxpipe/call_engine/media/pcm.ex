defmodule Vxpipe.CallEngine.Media.PCM do
  @moduledoc false

  @minimum_sample -32_768
  @maximum_sample 32_767

  @spec mix([binary()]) :: {:ok, binary()} | {:error, :invalid_pcm}
  def mix([payload | _rest] = payloads) when is_binary(payload) do
    if valid_payloads?(payloads, byte_size(payload)) do
      payloads
      |> Enum.map(&decode/1)
      |> Enum.zip_with(&mix_samples/1)
      |> encode()
      |> then(&{:ok, &1})
    else
      {:error, :invalid_pcm}
    end
  end

  def mix(_payloads), do: {:error, :invalid_pcm}

  defp valid_payloads?(payloads, size) do
    size > 0 and rem(size, 2) == 0 and
      Enum.all?(payloads, &(is_binary(&1) and byte_size(&1) == size))
  end

  defp decode(payload), do: for(<<sample::little-signed-16 <- payload>>, do: sample)

  defp mix_samples(samples) do
    samples
    |> Enum.sum()
    |> max(@minimum_sample)
    |> min(@maximum_sample)
  end

  defp encode(samples) do
    samples
    |> Enum.map(&<<&1::little-signed-16>>)
    |> IO.iodata_to_binary()
  end
end
