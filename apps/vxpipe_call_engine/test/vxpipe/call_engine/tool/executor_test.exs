defmodule Vxpipe.CallEngine.Tool.ExecutorTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Tool.{Call, Context, Executor}
  alias Vxpipe.CallEngine.Tool.CurrentTime

  test "executes a configured tool with bounded JSON-compatible output" do
    assert {:ok, registry} = Executor.new([CurrentTime], 4_096)
    call = %Call{id: "tool-1", name: "get_current_time", arguments: %{}}

    assert {:ok, result} = Executor.execute(registry, call, context())
    assert result["timezone"] == "UTC"
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(result["iso8601"])
  end

  test "rejects unknown tools and invalid arguments without invoking arbitrary modules" do
    assert {:ok, registry} = Executor.new([CurrentTime], 4_096)

    assert {:error, :unknown_tool} =
             Executor.execute(
               registry,
               %Call{id: "tool-1", name: "not_configured", arguments: %{}},
               context()
             )

    assert {:error, :invalid_arguments} =
             Executor.execute(
               registry,
               %Call{id: "tool-2", name: "get_current_time", arguments: %{"zone" => "local"}},
               context()
             )
  end

  test "rejects duplicate names and oversized results during configuration or execution" do
    assert {:error, :invalid_configuration} = Executor.new([CurrentTime, CurrentTime], 4_096)
    assert {:error, :invalid_configuration} = Executor.new([CurrentTime], 0)
  end

  defp context do
    %Context{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "rinc-test",
      agent_participant_id: "agent-test",
      source_participant_id: "participant-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "correlation-test"
    }
  end
end
