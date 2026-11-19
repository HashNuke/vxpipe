defmodule Vxpipe.CallEngine.Diagnostics.CapturePacketTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.CapturePacket
  alias Vxpipe.CallEngine.Media.AudioFrame

  test "acoustic progress contains only a bounded epoch and contiguous finalized interval" do
    for packet <- [{:acoustic_progress, 0, 0, 0}, {:acoustic_progress, 2, 512, 2_560}] do
      assert {:ok, charge} = CapturePacket.charge(packet)
      assert charge > 0
      assert CapturePacket.copy(packet) == packet
    end

    for packet <- [
          {:acoustic_progress, -1, 0, 512},
          {:acoustic_progress, 0, -1, 512},
          {:acoustic_progress, 0, 512, 511},
          {:acoustic_progress, 0, 0, 512.0},
          {:acoustic_progress, 0, 0, 9_223_372_036_854_775_808},
          {:acoustic_progress, 0, 0, 512, "private text"}
        ] do
      assert {:error, :invalid_evidence} = CapturePacket.charge(packet)
    end
  end

  test "a malformed frame cannot retain arbitrary metadata or crash the admission boundary" do
    frame = %AudioFrame{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "human",
      connection_id: "connection",
      track_id: "audio",
      codec: :linear16,
      sample_rate: 16_000,
      channels: 1,
      sequence_number: 1,
      timestamp: 0,
      payload: <<0, 0>>,
      received_at: 0
    }

    malformed = frame |> Map.delete(:tenant_id) |> Map.put(:transcript, "private text")
    assert {:error, :invalid_evidence} = CapturePacket.charge({:audio, malformed})
  end
end
