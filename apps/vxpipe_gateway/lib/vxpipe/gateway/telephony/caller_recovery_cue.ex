defmodule Vxpipe.Gateway.Telephony.CallerRecoveryCue do
  @moduledoc false
  alias Vxpipe.CallEngine.OpeningAudio.Asset

  def asset(kind) when kind in [:hearing, :repeat] do
    path = Application.app_dir(:vxpipe_gateway, "priv/telephony/#{kind}.s16le.gz")

    with {:ok, compressed} <- File.read(path) do
      payload = :zlib.gunzip(compressed)

      {:ok,
       %Asset{
         codec: :linear16,
         byte_order: :little,
         channels: 1,
         sample_rate: 48_000,
         duration_ms: div(byte_size(payload), 96),
         payload: payload
       }}
    end
  rescue
    ErlangError -> {:error, :invalid_audio}
  end
end
