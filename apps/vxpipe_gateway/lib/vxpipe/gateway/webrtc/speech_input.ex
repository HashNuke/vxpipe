defmodule Vxpipe.Gateway.WebRTC.SpeechInput do
  @moduledoc false

  alias Membrane.Opus.Decoder.Native
  alias Vxpipe.CallEngine.ConnectionAttachment
  alias Vxpipe.CallEngine.Media.Ingress

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
         {:ok, output, decoder} <- decoder(track, format) do
      {:ok, output, %{ingress: ingress, input: track, output: output, decoder: decoder}}
    end
  end

  def frame(frame, nil), do: {:ok, frame}
  def frame(frame, %{decoder: nil}), do: {:ok, frame}

  def frame(frame, %{decoder: decoder, output: output}) do
    case Native.decode_packet(decoder, frame.payload) do
      payload when is_binary(payload) ->
        {:ok,
         %{
           frame
           | codec: :linear16,
             sample_rate: output.sample_rate,
             channels: 1,
             timestamp: div(frame.timestamp * output.sample_rate, frame.sample_rate),
             payload: payload
         }}

      _invalid ->
        {:error, :invalid_packet}
    end
  end

  defp decoder(%{codec: codec, sample_rate: rate} = track, %{codec: codec, sample_rate: rate}),
    do: {:ok, track, nil}

  defp decoder(%{codec: :opus, sample_rate: 48_000} = track, %{
         codec: :linear16,
         sample_rate: rate
       })
       when rate in [8_000, 12_000, 16_000, 24_000, 48_000] do
    {:ok, %{track | codec: :linear16, sample_rate: rate, channels: 1}, Native.create(rate, 1)}
  end

  defp decoder(_track, _format), do: {:error, :unsupported_audio}
end
