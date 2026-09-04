defmodule Vxpipe.Gateway.WebRTC.OpusEncoderTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.WebRTC.OpusEncoder

  test "encodes one 20 ms 48 kHz mono linear16 frame" do
    assert {:ok, encoder} = OpusEncoder.new([])
    pcm = :binary.copy(<<0, 0>>, 960)
    assert {:ok, opus} = OpusEncoder.encode(encoder, pcm)
    assert is_binary(opus)
    assert byte_size(opus) > 0
    assert byte_size(opus) < byte_size(pcm)
  end

  test "rejects any input other than one exact frame" do
    assert {:ok, encoder} = OpusEncoder.new([])
    assert {:error, :invalid_pcm_frame} = OpusEncoder.encode(encoder, <<0, 0>>)
  end
end
