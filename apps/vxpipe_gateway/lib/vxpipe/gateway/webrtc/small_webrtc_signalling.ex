defmodule Vxpipe.Gateway.WebRTC.SmallWebRTCSignalling do
  @moduledoc false

  @spec encode_peer_left() :: binary()
  def encode_peer_left do
    JSON.encode!(%{
      "type" => "signalling",
      "message" => %{"type" => "peerLeft"}
    })
  end
end
