defmodule Vxpipe.CallEngine.Tool.HangupTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.RoomAuthority.CallerAnswer
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

  describe "CallerAnswer.terminal_admission/2" do
    test "an engine continuation is blocked while the caller's answer is outstanding" do
      {state, context} = engine_state_with_question()

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "an engine continuation proceeds once the caller has answered" do
      {state, context} = engine_state_with_question()
      state = CallerAnswer.accepted(state, %{connection_id: "conn-1"})

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "an engine continuation proceeds when nothing was asked" do
      {state, context} = engine_state_without_prompt()

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "a caller turn keeps its explicitly requested goodbye" do
      {state, context} = caller_state_with_question()

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "an engine continuation is blocked while an STT turn is active" do
      {state, context} = engine_state_without_prompt()

      connection = Map.fetch!(state.connections, "conn-1")
      speech_to_text = Map.put(connection.speech_to_text, :turn, %{command_id: "stt-turn"})
      state = put_in(state.connections["conn-1"], %{connection | speech_to_text: speech_to_text})

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "an unknown turn fails closed while a question is outstanding" do
      {state, _context} = engine_state_with_question()
      context = tool_context("cmd-unknown", "turn-unknown")

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "a prompt delivered to another voice does not block" do
      {state, context} = engine_state_with_question()
      state = %{state | text_capability: %{pid: spawn(fn -> :ok end)}}

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "a question already playing reserves the floor before its receipt" do
      {state, context} = engine_state_without_prompt()

      turn = %{
        command: send_command("cmd-playing", "turn-playing"),
        speech_requests: %{"out-1" => %{text: "Anything else?"}}
      }

      state = put_in(state.agent_turns[{"conn-1", "turn-playing", "cmd-playing"}], turn)

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "a playing statement does not reserve the floor" do
      {state, context} = engine_state_without_prompt()

      turn = %{
        command: send_command("cmd-playing", "turn-playing"),
        speech_requests: %{"out-1" => %{text: "Let me save that."}}
      }

      state = put_in(state.agent_turns[{"conn-1", "turn-playing", "cmd-playing"}], turn)

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "an engine greeting turn does not bypass the floor" do
      {state, _} = engine_state_with_question()
      context = tool_context("cmd-greet", "turn-greet", :engine)

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "an engine idle turn does not bypass the floor" do
      {state, _} = engine_state_with_question()
      context = tool_context("cmd-idle", "turn-idle", :engine)

      assert {:error, :caller_answer_pending} = CallerAnswer.terminal_admission(state, context)
    end

    test "a native STS turn keeps existing authority checks isolated from the room floor" do
      {state, _} = engine_state_with_question()
      context = tool_context("cmd-sts", "turn-sts", :sts)

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end

    test "settled speech without a pending request does not reserve the floor" do
      {state, context} = engine_state_without_prompt()

      turn = %{
        command: send_command("cmd-played", "turn-played"),
        speech_requests: %{},
        supported_segments: [{"out-1", "Saved."}]
      }

      state = put_in(state.agent_turns[{"conn-1", "turn-played", "cmd-played"}], turn)

      assert :ok = CallerAnswer.terminal_admission(state, context)
    end
  end

  defp engine_state_with_question do
    agent = self()
    turn = "turn-engine"
    command = continue_command("cmd-engine", turn)
    context = tool_context("cmd-engine", turn, :engine)

    state = %{
      text_capability: %{pid: agent},
      connections: %{
        "conn-1" => %{speech_to_text: %{turn: nil}, caller_prompt: {agent, true, "digest"}}
      },
      agent_turns: %{{"conn-1", turn, "cmd-engine"} => %{command: command}}
    }

    {state, context}
  end

  defp engine_state_without_prompt do
    agent = self()
    turn = "turn-engine"
    command = continue_command("cmd-engine", turn)
    context = tool_context("cmd-engine", turn, :engine)

    state = %{
      text_capability: %{pid: agent},
      connections: %{"conn-1" => %{speech_to_text: %{turn: nil}}},
      agent_turns: %{{"conn-1", turn, "cmd-engine"} => %{command: command}}
    }

    {state, context}
  end

  defp caller_state_with_question do
    agent = self()
    turn = "turn-caller"
    command = send_command("cmd-caller", turn)
    context = tool_context("cmd-caller", turn, :caller)

    state = %{
      text_capability: %{pid: agent},
      connections: %{
        "conn-1" => %{speech_to_text: %{turn: nil}, caller_prompt: {agent, true, "digest"}}
      },
      agent_turns: %{{"conn-1", turn, "cmd-caller"} => %{command: command}}
    }

    {state, context}
  end

  defp continue_command(id, correlation) do
    %ContinueAgent{
      id: id,
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller",
      connection_id: "conn-1",
      correlation_id: correlation,
      content: "engine observation",
      audio_response: true,
      source_command_id: "origin",
      tool_call_id: "tool-1",
      tool_name: "update_variable"
    }
  end

  defp send_command(id, correlation) do
    %SendText{
      id: id,
      tenant_id: "tenant",
      actor_id: "actor",
      room_id: "room",
      incarnation_id: "incarnation",
      participant_id: "caller",
      connection_id: "conn-1",
      correlation_id: correlation,
      content: "Goodbye.",
      run_immediately: true,
      audio_response: true,
      deadline: DateTime.utc_now()
    }
  end

  defp tool_context(command_id, correlation_id, origin \\ :engine) do
    %Context{
      tenant_id: "tenant",
      room_id: "room",
      incarnation_id: "incarnation",
      agent_participant_id: "agent",
      source_participant_id: "caller",
      connection_id: "conn-1",
      command_id: command_id,
      correlation_id: correlation_id,
      request_origin: origin
    }
  end
end
