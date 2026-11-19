defmodule Vxpipe.Console.DiagnosticConnectionFixtureTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Console.Test.SpeechConnection

  for mode <- [true, :scoped] do
    test "audit mode #{inspect(mode)} preserves events and the intended recipient identity" do
      mode = unquote(mode)

      command = %{
        tenant_id: "tenant",
        room_id: "room",
        incarnation_id: "incarnation",
        participant_id: "human",
        connection_id: "connection"
      }

      connection =
        start_supervised!(
          {SpeechConnection, command: command, observer: self(), audit_events?: mode}
        )

      event = %{room_id: "room", connection_id: "other-source", id: "event"}
      send(connection, {:vxpipe_event, event})

      assert_audit(mode, connection, event)
      assert_receive {:vxpipe_event, ^event}
      refute_received {:configured_public_event, _}
      refute_received {:configured_public_event, _, _}
    end
  end

  defp assert_audit(:scoped, connection, event),
    do: assert_receive({:configured_public_event, ^connection, ^event})

  defp assert_audit(true, _connection, event),
    do: assert_receive({:configured_public_event, ^event})
end
