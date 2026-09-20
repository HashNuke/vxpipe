defmodule Vxpipe.Gateway.WebRTC.OpusDecoder do
  @moduledoc false

  alias __MODULE__.Native

  @rates [8_000, 12_000, 16_000, 24_000, 48_000]

  @spec new(pos_integer()) :: {:ok, reference()} | {:error, :unsupported_audio}
  def new(sample_rate) when sample_rate in @rates do
    {:ok, Native.create(sample_rate)}
  rescue
    _exception -> {:error, :unsupported_audio}
  end

  def new(_sample_rate), do: {:error, :unsupported_audio}

  @spec decode(reference(), binary()) :: {:ok, binary()} | {:error, :invalid_packet}
  def decode(decoder, payload) when is_binary(payload) do
    {:ok, Native.decode_packet(decoder, payload)}
  rescue
    _exception -> {:error, :invalid_packet}
  end
end
