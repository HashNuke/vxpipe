defmodule Vxpipe.CallEngine.Tool.HangupTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Tool.{Context, Hangup}

  @tag :protected_announcement
  test "a valid announcement distinguishes room loss from invalid text" do
    context = %Context{
      tenant_id: "absent-hangup-tenant",
      room_id: "absent-hangup-room",
      incarnation_id: "incarnation",
      agent_participant_id: "agent",
      source_participant_id: "human",
      connection_id: "caller",
      command_id: "origin-command",
      correlation_id: "origin-turn",
      tool_call_id: "hangup"
    }

    assert {:error, :invalid_arguments} = Hangup.execute(%{"announcement" => "   "}, context)
    assert {:error, :unavailable} = Hangup.execute(%{"announcement" => "Goodbye."}, context)
  end
end
