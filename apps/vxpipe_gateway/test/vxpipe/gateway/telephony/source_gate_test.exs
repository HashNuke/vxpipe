defmodule Vxpipe.Gateway.Telephony.SourceGateTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Gateway.Telephony.SourceGate

  test "admits every epoch before any cutover" do
    gate = SourceGate.new()

    assert SourceGate.admitted?(gate, make_ref())
    assert SourceGate.admitted?(gate, nil)
    refute SourceGate.held?(gate)
  end

  test "drops every epoch while held and records the held epoch on re-hold" do
    held_epoch = make_ref()
    gate = SourceGate.hold(SourceGate.new())

    assert gate == {:held, nil}
    assert SourceGate.held?(gate)
    refute SourceGate.admitted?(gate, held_epoch)
    refute SourceGate.admitted?(gate, nil)

    active = SourceGate.arm(gate, held_epoch)
    assert active == {:active, held_epoch}

    reheld = SourceGate.hold(active)
    assert reheld == {:held, held_epoch}
    refute SourceGate.admitted?(reheld, held_epoch)
  end

  test "admits only the exact active epoch after arm" do
    active_epoch = make_ref()
    gate = SourceGate.arm(SourceGate.hold(SourceGate.new()), active_epoch)

    assert SourceGate.admitted?(gate, active_epoch)
    refute SourceGate.admitted?(gate, make_ref())
    refute SourceGate.admitted?(gate, nil)
  end
end
