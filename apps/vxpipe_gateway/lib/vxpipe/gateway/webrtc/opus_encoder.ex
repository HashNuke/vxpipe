defmodule Vxpipe.Gateway.WebRTC.OpusEncoder do
  @moduledoc false

  alias Membrane.Opus.Encoder.Native

  @application_voip 2_048
  @automatic_bitrate -1_000
  @channels 1
  @frame_bytes 1_920
  @frame_samples 960
  @sample_rate 48_000
  @signal_voice 3_001

  def new(_options) do
    {:ok,
     Native.create(
       @sample_rate,
       @channels,
       @application_voip,
       @automatic_bitrate,
       @signal_voice
     )}
  rescue
    _exception -> {:error, :encoder_unavailable}
  end

  def encode(encoder, pcm) when is_binary(pcm) and byte_size(pcm) == @frame_bytes do
    case Native.encode_packet(encoder, pcm, @frame_samples) do
      {:ok, opus} when is_binary(opus) and byte_size(opus) > 0 -> {:ok, opus}
      {:error, _reason} -> {:error, :encode_failed}
    end
  end

  def encode(_encoder, _pcm), do: {:error, :invalid_pcm_frame}
end
