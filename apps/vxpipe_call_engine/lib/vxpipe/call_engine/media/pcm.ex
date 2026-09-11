defmodule Vxpipe.CallEngine.Media.PCM do
  @moduledoc false

  alias Membrane.AudioMixer.Adder
  alias Membrane.RawAudio

  @stream_format %RawAudio{sample_format: :s16le, sample_rate: 48_000, channels: 1}

  @spec mix([binary()]) :: {:ok, binary()} | {:error, :invalid_pcm}
  def mix([payload | _rest] = payloads) when is_binary(payload) do
    if valid_payloads?(payloads, byte_size(payload)) do
      mixer = Adder.init(@stream_format)
      {payload, _mixer} = Adder.mix(payloads, mixer)
      {:ok, payload}
    else
      {:error, :invalid_pcm}
    end
  end

  def mix(_payloads), do: {:error, :invalid_pcm}

  defp valid_payloads?(payloads, size) do
    size > 0 and rem(size, 2) == 0 and
      Enum.all?(payloads, &(is_binary(&1) and byte_size(&1) == size))
  end
end
