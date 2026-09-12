defmodule Vxpipe.Persistence.ArchiveRecordCodecTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Persistence.ArchiveRecordCodec

  test "decodes an allow-listed persisted kind through the Calls contract" do
    stored = %{
      public_id: "event-id",
      kind: "participant_joined",
      sequence: 1,
      room_id: "room-id",
      incarnation_id: "incarnation-id",
      participant_id: "participant-id",
      activation_id: nil,
      source_participant_id: nil,
      connection_id: nil,
      command_id: "command-id",
      correlation_id: nil,
      tool_call_id: nil,
      public_sequence: nil,
      occurred_at: ~U[2026-09-12 08:45:26.238000Z],
      source_policy: %{"revision" => 0},
      payload: %{"role" => "human", "state" => "joined"}
    }

    assert {:ok, fact} = ArchiveRecordCodec.call_fact(stored, "tenant-key", "call-id")
    assert Atom.to_string(fact.kind) == stored.kind
  end
end
