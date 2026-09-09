defmodule Vxpipe.CallEngine.Archive.PortTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff, Port, Supervisor}
  alias Vxpipe.CallEngine.TestCollectingArchiveWriter

  test "hands off an inspect-redacted fact with credentials removed and stable ordering" do
    handoff = open_archive()

    port =
      Port.new(
        handoff,
        %{
          tenant_id: "tenant-archive",
          call_id: "call-archive",
          room_id: "room-archive",
          incarnation_id: "rinc-archive"
        },
        %{"revision" => 7}
      )

    occurred_at = ~U[2026-09-09 12:00:00.123Z]

    port =
      Port.emit(port, :accepted_input,
        id: "evt-accepted",
        participant_id: "part-caller",
        connection_id: "conn-caller",
        command_id: "cmd-input",
        correlation_id: "turn-input",
        occurred_at: occurred_at,
        payload: %{
          "content" => "Keep this transcript",
          "request" => %{
            "headers" => %{
              "Authorization" => "Bearer must-not-survive",
              "X-Trace-Id" => "trace-1"
            },
            "api_key" => "must-not-survive"
          }
        }
      )

    _port =
      Port.emit(port, :participant_turn_completed,
        id: "evt-completed",
        participant_id: "part-caller",
        connection_id: "conn-caller",
        command_id: "cmd-input",
        correlation_id: "turn-input",
        occurred_at: occurred_at,
        public_sequence: 4,
        payload: %{"modality" => "text"}
      )

    assert_receive {:test_archive_fact,
                    %Fact{
                      id: "evt-accepted",
                      kind: :accepted_input,
                      sequence: 1,
                      tenant_id: "tenant-archive",
                      call_id: "call-archive",
                      room_id: "room-archive",
                      incarnation_id: "rinc-archive",
                      participant_id: "part-caller",
                      connection_id: "conn-caller",
                      command_id: "cmd-input",
                      correlation_id: "turn-input",
                      occurred_at: ^occurred_at,
                      public_sequence: nil,
                      source_policy: %{"revision" => 7},
                      payload: first_payload
                    }},
                   1_000

    assert first_payload == %{
             "content" => "Keep this transcript",
             "request" => %{"headers" => %{"X-Trace-Id" => "trace-1"}}
           }

    refute inspect(first_payload) =~ "must-not-survive"

    refute inspect(%Fact{
             id: "evt-accepted",
             kind: :accepted_input,
             sequence: 1,
             tenant_id: "tenant-archive",
             call_id: "call-archive",
             room_id: "room-archive",
             incarnation_id: "rinc-archive",
             occurred_at: occurred_at,
             source_policy: %{},
             payload: %{"content" => "private-transcript"}
           }) =~ "private-transcript"

    assert_receive {:test_archive_fact,
                    %Fact{
                      id: "evt-completed",
                      kind: :participant_turn_completed,
                      sequence: 2,
                      public_sequence: 4
                    }},
                   1_000
  end

  defp open_archive do
    assert {:ok, handoff} =
             Supervisor.open(
               writer: {TestCollectingArchiveWriter, self()},
               maximum_pending_facts: 8,
               retry_delay_ms: 5,
               drain_timeout_ms: 1_000
             )

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end
end
