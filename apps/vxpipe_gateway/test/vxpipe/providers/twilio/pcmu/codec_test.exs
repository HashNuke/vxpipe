defmodule Vxpipe.Providers.Twilio.PCMU.CodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.Twilio.PCMU.Codec

  test "encodes and decodes standard mu-law boundary vectors" do
    pcm =
      <<0::little-signed-16, -1::little-signed-16, 32_124::little-signed-16,
        -32_124::little-signed-16>>

    assert {:ok, <<0xFF, 0x7F, 0x80, 0x00>>} = Codec.encode(pcm)

    assert {:ok,
            <<0::little-signed-16, 0::little-signed-16, 32_124::little-signed-16,
              -32_124::little-signed-16>>} = Codec.decode(<<0xFF, 0x7F, 0x80, 0x00>>)
  end

  test "rejects incomplete linear PCM samples" do
    assert {:error, :invalid_linear_pcm} = Codec.encode(<<0>>)
  end
end
