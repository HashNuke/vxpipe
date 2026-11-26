defmodule Vxpipe.CallEngine.CompletionTerminalActionRoomTest do
  use ExUnit.Case, async: false

  import Vxpipe.CallEngine.TestVoiceToolRoom

  alias Vxpipe.AgentRuntime.{ModelResponse, ToolCall}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ToolCallCompleted}

  setup do
    configure()
  end

  for settled? <- [true, false], action <- [:hangup, :transfer] do
    test "a private completion cannot #{action} with question receipt settled = #{settled?}" do
      {_plan, room, caller, voice, sink} =
        start_call(
          billing_transfer: unquote(action) == :transfer,
          tools: %{"end_call" => %{type: "platform", tool: "hangup"}},
          variable_permissions: %{"intake" => ["read", "write"]},
          call_variables: %{
            "intake" => %{
              schema: %{"type" => "object", "properties" => %{"area" => %{"type" => "string"}}}
            }
          }
        )

      submit(room, caller, "Florida", "area")
      assert_receive {:test_agent_runtime_stream, first, _}

      {:ok, write} =
        ToolCall.new(
          id: "save",
          name: "update_variable",
          arguments: %{
            "section_name" => "intake",
            "variable_name" => "area",
            "variable_value" => "Florida"
          }
        )

      question = "Anything else?"

      preamble =
        JSON.encode!(%{
          "type" => "participant_message",
          "agent_mode" => "speaker",
          "participant_id" => "agent",
          "message" => question
        })

      send_response(first, preamble, write)

      assert_receive {:vxpipe_event,
                      %ToolCallCompleted{tool_call_id: "save", result: %{"revision" => 1}}}

      assert_receive {:test_tts_control, ^voice, speak}
      assert JSON.decode!(speak)["text"] == question
      if unquote(settled?), do: settle(voice, sink, "question", "area")

      assert_receive {:test_agent_runtime_stream, followup, observation}
      assert List.last(observation.messages).content =~ "Florida"

      {:ok, terminal} = terminal_call(unquote(action))

      send_response(followup, "", terminal)
      assert_receive {:test_agent_runtime_stream, correction, rejected}

      assert JSON.decode!(List.last(rejected.messages).content) ==
               %{"status" => "rejected", "reason" => "caller_answer_pending"}

      reply(correction, :listener, nil)
      unless unquote(settled?), do: settle(voice, sink, "question", "area")

      completion_turn = observation.correlation.tool_context.correlation_id
      assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: ^completion_turn}}
      refute_received {:test_tts_control, ^voice, _}
      submit(room, caller, "Yes, what about trees?", "trees")
      assert_receive {:test_agent_runtime_stream, agent, request}
      assert List.last(request.messages).content =~ "trees"
      reply(agent, :speaker, "We trim trees.")
      assert_receive {:test_tts_control, ^voice, heard}
      assert JSON.decode!(heard)["text"] == "We trim trees."
      settle(voice, sink, "trees", "trees")
    end
  end

  defp terminal_call(:hangup),
    do:
      ToolCall.new(id: "premature", name: "end_call", arguments: %{"announcement" => "Goodbye."})

  defp terminal_call(:transfer),
    do:
      ToolCall.new(
        id: "premature",
        name: "transfer",
        arguments: %{"destination" => "billing", "announcement" => "Transferring."}
      )

  defp send_response(provider, text, call) do
    {:ok, response} = ModelResponse.new(text: text, tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end
end
