defmodule Vxpipe.CallEngine.TenantCommandTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Command

  @commands [
    Command.CreateRoom,
    Command.JoinParticipant,
    Command.AttachConnection,
    Command.SendText,
    Command.ParticipantTransferControl,
    Command.ReadCallVariables,
    Command.UpdateCallVariables
  ]

  for command <- @commands do
    test "#{inspect(command)} accepts the complete URL-safe tenant-key alphabet" do
      command = unquote(command)

      for key <- ["_234567890123456", "-234567890123456"] do
        assert {:ok, result} = command.new(Keyword.put(options(), :tenant_id, key))
        assert result.tenant_id == key
      end
    end

    test "#{inspect(command)} retains tenant bounds and other identifier validation" do
      command = unquote(command)

      for key <- [nil, "", "../tenant", "tenant/key", "tenant key", String.duplicate("a", 129)] do
        assert {:error, error} = command.new(Keyword.put(options(), :tenant_id, key))
        assert error.code == :invalid_command
        assert error.details["field"] == "tenant_id"
      end

      assert {:error, error} = command.new(Keyword.put(options(), :room_id, "_room"))
      assert error.details["field"] == "room_id"
    end
  end

  defp options do
    [
      tenant_id: "tenant-command",
      actor_id: "actor",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "participant",
      source_participant_id: "source",
      connection_id: "connection",
      correlation_id: "correlation",
      activation_id: "activation",
      tool_call_id: "tool",
      attempt_id: "attempt",
      role: :human,
      action: :accept,
      content: "Hello",
      sections: ["profile"],
      section: "profile",
      expected_revision: 0,
      operation: {:merge, %{"name" => "Example"}},
      deadline: DateTime.add(DateTime.utc_now(), 10, :second)
    ]
  end
end
