defmodule Vxpipe.CallEngine.ScribeTransportReceiptTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.TestElevenLabsScribeTransport, as: Wire

  test "optional receipts timestamp provider handling and retain frame order" do
    wire =
      start_supervised!(
        {Wire, owner: self(), transport_options: [observer: self(), timed_audio: true]}
      )

    before_us = System.monotonic_time(:microsecond)
    assert :ok = Wire.send_audio(wire, <<1, 2>>)
    after_us = System.monotonic_time(:microsecond)
    assert_receive {:scribe_audio, ^wire, 0, <<1, 2>>, at_us}
    assert before_us <= at_us and at_us <= after_us
    assert :ok = Wire.send_audio(wire, <<3, 4>>)
    assert_receive {:scribe_audio, ^wire, 1, <<3, 4>>, next_us}
    assert next_us >= at_us
  end

  test "ordinary fixtures keep the existing event shape" do
    wire = start_supervised!({Wire, owner: self(), transport_options: [observer: self()]})
    assert :ok = Wire.send_audio(wire, <<1, 2>>)
    assert_receive {:scribe_audio, ^wire, <<1, 2>>}
    refute_received {:scribe_audio, ^wire, _, _, _}
  end
end
