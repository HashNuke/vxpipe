defmodule Vxpipe.Gateway.Telephony.CallerRecoveryCueTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.OpeningAudio.Asset
  alias Vxpipe.Gateway.Telephony.CallerRecoveryCue

  test "hearing and repeat cues are distinct playable mono PCM recordings" do
    for kind <- [:hearing, :repeat] do
      assert {:ok, %Asset{sample_rate: 48_000, channels: 1, codec: :linear16} = asset} =
               CallerRecoveryCue.asset(kind)

      assert asset.duration_ms in 500..4_500
      assert div(byte_size(asset.payload), 96) == asset.duration_ms
      refute asset.payload == :binary.copy(<<0>>, byte_size(asset.payload))
    end

    refute CallerRecoveryCue.asset(:hearing) == CallerRecoveryCue.asset(:repeat)
  end
end
