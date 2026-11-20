defmodule Vxpipe.CallEngine.Diagnostics.InferenceTapCloseTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.{CallSettings, CaptureHandoff, InferenceTap}
  alias Vxpipe.CallEngine.Speech.Silero

  test "explicit clean settlement witnesses the exact contiguous accepted source end before reset" do
    {:ok, handoff} =
      CaptureHandoff.new(self(), settings: CallSettings.new(%{enabled: true, revision: 1}))

    tap = InferenceTap.attach(nil, handoff, 4, Silero.new(), false, true)
    tap = InferenceTap.accept(tap, 4, 32_000, 320)
    tap = InferenceTap.accept(tap, 4, 32_320, 320)
    _ = InferenceTap.reset(tap, 5, true)
    assert {:operational_epoch_closed, 4, 32_000, 32_640, _} = packet(handoff)
    assert {:reset, 5, :provider_turn_settled, _} = packet(handoff)
  end

  test "unclean, unmapped or unattached history cannot issue a clean-close witness" do
    for mode <- [:unclean, :gap, :late] do
      {:ok, handoff} =
        CaptureHandoff.new(self(), settings: CallSettings.new(%{enabled: true, revision: 1}))

      tap = InferenceTap.attach(nil, handoff, 4, Silero.new(), mode == :late, true)
      if mode == :late, do: assert({:reset, 4, :partial_start, _} = packet(handoff))
      tap = InferenceTap.accept(tap, 4, 32_000, 320)
      tap = if mode == :gap, do: InferenceTap.accept(tap, 4, 32_321, 320), else: tap
      if mode == :gap, do: assert({:reset, 4, :audio_gap, _} = packet(handoff))
      _ = InferenceTap.reset(tap, 5, mode != :unclean)
      assert {:reset, 5, :provider_turn_settled, _} = packet(handoff)
      if mode == :unclean, do: assert({:reset, 5, :partial_start, _} = packet(handoff))
      refute_received {:vxpipe_diagnostic_capture, _, _, _, _}
    end
  end

  defp packet(handoff) do
    assert_receive {:vxpipe_diagnostic_capture, _, _, _, _} = message
    assert {:ok, packet, charge} = CaptureHandoff.message(handoff, message)
    CaptureHandoff.release(handoff, charge, :processed)
    packet
  end
end
