defmodule Vxpipe.Calls.EngineArchiveProjectionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.Calls.EngineArchiveProjection

  test "accepts private participant-transfer lifecycle facts" do
    for kind <- [
          :participant_transfer_started,
          :participant_transfer_completed,
          :participant_transfer_failed
        ] do
      engine_fact = transfer_fact(kind)

      assert {:ok, projected} = EngineArchiveProjection.project(engine_fact)
      assert projected.kind == kind
      assert projected.participant_id == "part-reception"
      assert projected.activation_id == "act-reception"
      assert projected.source_participant_id == "part-caller"
      assert projected.tool_call_id == "transfer-1"
      assert projected.payload == engine_fact.payload
    end
  end

  defp transfer_fact(kind) do
    Fact.new!(
      id: "event-#{kind}",
      kind: kind,
      sequence: 7,
      tenant_id: "AAAAAAAAAAAAAAAA",
      call_id: "44444444-4444-4444-8444-444444444444",
      room_id: "55555555-5555-4555-8555-555555555555",
      incarnation_id: "rinc-transfer",
      participant_id: "part-reception",
      activation_id: "act-reception",
      source_participant_id: "part-caller",
      connection_id: "conn-caller",
      command_id: "command-transfer",
      correlation_id: "turn-transfer",
      tool_call_id: "transfer-1",
      occurred_at: ~U[2026-09-11 00:00:00.000Z],
      source_policy: %{"revision" => 1},
      payload: %{
        "destination_call_spec_key" => "billing",
        "destination_participant_id" => "part-billing",
        "source_call_spec_key" => "reception"
      }
    )
  end
end
