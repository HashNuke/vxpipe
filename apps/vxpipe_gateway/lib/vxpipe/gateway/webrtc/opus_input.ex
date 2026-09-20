defmodule Vxpipe.Gateway.WebRTC.OpusInput do
  @moduledoc false

  alias ExWebRTC.RTPCodecParameters

  @spec supported?(RTPCodecParameters.t()) :: boolean()
  def supported?(%RTPCodecParameters{
        mime_type: mime_type,
        clock_rate: 48_000,
        channels: channels
      })
      when is_binary(mime_type) and channels in [nil, 1, 2] do
    String.downcase(mime_type) == "audio/opus"
  end

  def supported?(%RTPCodecParameters{}), do: false

  @spec channels(RTPCodecParameters.t(), binary()) ::
          {:ok, 1 | 2} | {:error, :invalid_packet | :unsupported_codec}
  def channels(%RTPCodecParameters{} = codec, payload) when is_binary(payload) do
    if supported?(codec), do: packet_channels(payload), else: {:error, :unsupported_codec}
  end

  @spec packet_channels(binary()) :: {:ok, 1 | 2} | {:error, :invalid_packet}
  def packet_channels(<<_configuration::5, stereo::1, _frame_code::2, _rest::binary>>),
    do: {:ok, stereo + 1}

  def packet_channels(<<>>), do: {:error, :invalid_packet}

  @spec track_channels(RTPCodecParameters.t()) ::
          {:ok, 1 | 2} | {:error, :unsupported_codec}
  def track_channels(%RTPCodecParameters{} = codec) do
    if supported?(codec), do: {:ok, codec.channels || 2}, else: {:error, :unsupported_codec}
  end
end
