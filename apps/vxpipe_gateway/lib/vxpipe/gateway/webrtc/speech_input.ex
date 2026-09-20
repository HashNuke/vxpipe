defmodule Vxpipe.Gateway.WebRTC.SpeechInput do
  @moduledoc false

  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.Ingress
  alias Vxpipe.Gateway.WebRTC.{OpusDecoder, OpusEncoder, OpusInput}

  def prepare(%ConnectionAttachment{media_ingress: nil}, track, _current),
    do: {:ok, track, nil}

  def prepare(
        %ConnectionAttachment{media_ingress: ingress},
        track,
        %{ingress: ingress, input: track} = current
      ),
      do: {:ok, current.output, current}

  def prepare(%ConnectionAttachment{media_ingress: ingress}, track, _current) do
    with {:ok, format} <- Ingress.media_format(ingress),
         {:ok, output, configured} <- configure(track, format) do
      input =
        if configured,
          do: Map.put(configured, :ingress, ingress),
          else: %{ingress: ingress, input: track, output: output, normalizer: nil}

      {:ok, output, input}
    end
  end

  def frame(frame, nil), do: {:ok, frame}
  def frame(frame, %{normalizer: nil}), do: {:ok, frame}

  def frame(frame, %{normalizer: mode, decoder: decoder, output: output} = input) do
    with {:ok, channels} <- OpusInput.packet_channels(frame.payload),
         {:ok, mono} <- OpusDecoder.decode(decoder, frame.payload),
         {:ok, payload} <- normalize_payload(mode, channels, frame.payload, mono, input) do
      {:ok,
       %{
         frame
         | codec: output.codec,
           sample_rate: output.sample_rate,
           channels: 1,
           timestamp: div(frame.timestamp * output.sample_rate, frame.sample_rate),
           payload: payload
       }}
    else
      _invalid -> {:error, :invalid_packet}
    end
  rescue
    _exception -> {:error, :invalid_packet}
  end

  @doc false
  def configure(%{codec: :opus, sample_rate: 48_000} = track, %{
        codec: :linear16,
        sample_rate: rate,
        channels: 1
      })
      when rate in [8_000, 12_000, 16_000, 24_000, 48_000] do
    output = %{track | codec: :linear16, sample_rate: rate, channels: 1}

    with {:ok, normalizer} <- normalizer(:linear16, rate) do
      configured = Map.merge(normalizer, %{input: track, output: output})
      {:ok, output, configured}
    end
  rescue
    _exception -> {:error, :unsupported_audio}
  end

  def configure(%{codec: :opus, sample_rate: 48_000} = track, %{
        codec: :opus,
        sample_rate: 48_000,
        channels: 1
      }) do
    with {:ok, encoder} <- OpusEncoder.new([]),
         {:ok, normalizer} <- normalizer(:opus, 48_000) do
      output = %{track | channels: 1}

      configured = Map.merge(normalizer, %{encoder: encoder, input: track, output: output})

      {:ok, output, configured}
    end
  rescue
    _exception -> {:error, :unsupported_audio}
  end

  def configure(
        %{codec: codec, sample_rate: rate, channels: channels} = track,
        %{codec: codec, sample_rate: rate, channels: channels}
      ) do
    {:ok, track, nil}
  end

  def configure(_track, _format), do: {:error, :unsupported_audio}

  defp normalizer(mode, rate) do
    with {:ok, decoder} <- OpusDecoder.new(rate) do
      {:ok, %{normalizer: mode, decoder: decoder}}
    end
  end

  defp normalize_payload(:linear16, _channels, _source, mono, _input), do: {:ok, mono}

  defp normalize_payload(:opus, _channels, _source, mono, %{encoder: encoder}) do
    OpusEncoder.encode(encoder, mono, div(byte_size(mono), 2))
  end
end
