defmodule Vxpipe.CallEngine.OpeningAudio.WaveDecoder do
  @moduledoc false

  alias Vxpipe.CallEngine.OpeningAudio.Asset

  @sample_rate 48_000
  @channels 1
  @bits_per_sample 16
  @block_align 2
  @byte_rate 96_000

  @spec decode(binary(), keyword()) ::
          {:ok, Asset.t()}
          | {:error, :audio_too_long | :unsupported_audio_format}
  def decode(wave, options) when is_binary(wave) and is_list(options) do
    maximum_duration_ms = Keyword.fetch!(options, :maximum_duration_ms)

    with {:ok, chunks} <- riff_chunks(wave),
         {:ok, format, pcm} <- required_chunks(chunks),
         :ok <- validate_format(format),
         :ok <- validate_pcm(pcm, maximum_duration_ms) do
      {:ok,
       %Asset{
         codec: :linear16,
         sample_rate: @sample_rate,
         channels: @channels,
         byte_order: :little,
         duration_ms: div(byte_size(pcm) * 1_000, @byte_rate),
         payload: pcm
       }}
    end
  end

  defp riff_chunks(<<"RIFF", declared_size::little-32, "WAVE", chunks::binary>> = wave)
       when declared_size + 8 == byte_size(wave) do
    parse_chunks(chunks, %{})
  end

  defp riff_chunks(_wave), do: unsupported()

  defp parse_chunks(<<>>, chunks), do: {:ok, chunks}

  defp parse_chunks(<<id::binary-size(4), size::little-32, rest::binary>>, chunks)
       when byte_size(rest) >= size do
    <<contents::binary-size(size), remainder::binary>> = rest
    padding = rem(size, 2)

    with {:ok, remainder} <- drop_padding(remainder, padding),
         {:ok, chunks} <- put_chunk(chunks, id, contents) do
      parse_chunks(remainder, chunks)
    end
  end

  defp parse_chunks(_incomplete, _chunks), do: unsupported()

  defp drop_padding(remainder, 0), do: {:ok, remainder}
  defp drop_padding(<<_padding, remainder::binary>>, 1), do: {:ok, remainder}
  defp drop_padding(_remainder, 1), do: unsupported()

  defp put_chunk(chunks, "fmt ", contents), do: put_once(chunks, :format, contents)
  defp put_chunk(chunks, "data", contents), do: put_once(chunks, :pcm, contents)
  defp put_chunk(chunks, _unknown, _contents), do: {:ok, chunks}

  defp put_once(chunks, key, value) do
    if Map.has_key?(chunks, key), do: unsupported(), else: {:ok, Map.put(chunks, key, value)}
  end

  defp required_chunks(%{format: format, pcm: pcm}), do: {:ok, format, pcm}
  defp required_chunks(_chunks), do: unsupported()

  defp validate_format(
         <<1::little-16, @channels::little-16, @sample_rate::little-32, @byte_rate::little-32,
           @block_align::little-16, @bits_per_sample::little-16, _extension::binary>>
       ),
       do: :ok

  defp validate_format(_format), do: unsupported()

  defp validate_pcm(pcm, maximum_duration_ms)
       when is_integer(maximum_duration_ms) and maximum_duration_ms > 0 and
              byte_size(pcm) > 0 and rem(byte_size(pcm), @block_align) == 0 do
    if byte_size(pcm) * 1_000 <= maximum_duration_ms * @byte_rate do
      :ok
    else
      {:error, :audio_too_long}
    end
  end

  defp validate_pcm(_pcm, _maximum_duration_ms), do: unsupported()

  defp unsupported, do: {:error, :unsupported_audio_format}
end
