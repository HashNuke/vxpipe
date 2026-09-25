defmodule Vxpipe.CallEngine.Provider.MorseCodeDuplex.ClockTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Provider.MorseCodeDuplex.Clock

  test "an ordinary tick emits the frames that are due" do
    assert Clock.frames_due(0, 40, 0) == {2, 0, 2, false}
    assert Clock.frames_due(0, 40, 2) == {0, 0, 2, false}
    assert Clock.frames_due(0, 100, 0, 10, 20) == {10, 0, 10, false}
  end

  test "a late tick emits the whole due backlog up to the catch-up bound" do
    assert Clock.frames_due(0, 100, 0) == {5, 0, 5, false}
    assert Clock.frames_due(0, 99, 1) == {3, 0, 4, false}
  end

  test "a stall beyond the catch-up bound moves the origin and reports it" do
    assert Clock.frames_due(0, 1_000, 0) == {5, 900, 5, true}
    assert Clock.frames_due(0, 1_000, 10) == {5, 700, 15, true}
  end

  test "a now before the origin never produces negative frames" do
    assert Clock.frames_due(100, 50, 0) == {0, 100, 0, false}
  end
end
