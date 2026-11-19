defmodule Vxpipe.CallEngine.Diagnostics.CapturePacketTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Diagnostics.CapturePacket
  alias Vxpipe.CallEngine.Media.AudioFrame

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
