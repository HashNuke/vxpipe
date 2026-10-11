defmodule Vxpipe.CallEngine.Speech.STTActivityPCM do
  @moduledoc false
  alias Vxpipe.CallEngine.Media.{AudioFrame, PCMResampler}

  @maximum_bytes 131_072
  @maximum_normalized_bytes 96_000

  @doc false
  def normalize_payload(pcm, timestamp, rate),
    do: normalize_pcm(pcm, timestamp, rate, 1, byte_size(pcm))

  def normalize(%AudioFrame{codec: :linear16, activity_pcm: nil} = frame) do
    normalize_pcm(
      frame.payload,
      frame.timestamp,
      frame.sample_rate,
      frame.channels,
      byte_size(frame.payload)
    )
  end

  def normalize(%AudioFrame{codec: :opus, activity_pcm: decoded} = frame)
      when is_map(decoded) and map_size(decoded) == 4 do
    case decoded do
      %{payload: pcm, timestamp: timestamp, sample_rate: rate, channels: 1}
      when timestamp == frame.timestamp and rate == frame.sample_rate and is_binary(pcm) ->
        normalize_pcm(
          pcm,
          timestamp,
          rate,
          frame.channels,
          byte_size(frame.payload) + byte_size(pcm)
        )

      _invalid ->
        {:error, :unsupported_audio}
    end
  end

  def normalize(_frame), do: {:error, :unsupported_audio}

  defp normalize_pcm(pcm, timestamp, rate, 1, bytes)
       when is_binary(pcm) and byte_size(pcm) > 0 and rem(byte_size(pcm), 2) == 0 and
              is_integer(timestamp) and timestamp >= 0 and
              is_integer(rate) and rate > 0 and
              2 * div(div(byte_size(pcm), 2) * 16_000 + rate - 1, rate) <=
                @maximum_normalized_bytes and
              bytes <= @maximum_bytes do
    {normalized, timestamp} = PCMResampler.resample(pcm, timestamp, rate, 16_000)
    {:ok, normalized, timestamp}
  end

  defp normalize_pcm(_pcm, _timestamp, _rate, _channels, _bytes),
    do: {:error, :unsupported_audio}
end
