defmodule Vxpipe.CallEngine.AgentTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

  alias Jido.AI.Runtime.Event
  alias Vxpipe.CallEngine.Agent
  alias Vxpipe.CallEngine.AgentFactory
  alias Vxpipe.CallEngine.TestAgentTool
  alias Vxpipe.CallEngine.Tool.Context
  alias Vxpipe.CallEngine.Tool.CurrentTime
  alias Vxpipe.CallEngine.Tool.Dispatcher

  test "pins the prompt, finite tool surface, and request policy before readiness" do
    agent_server = start_agent_server("act-test")

    assert :ok =
             AgentFactory.configure(
               agent_server,
               system_prompt: "Use the clock when asked.",
               tools: [CurrentTime]
             )

    assert {:ok, state} = Jido.AgentServer.state(agent_server)
    agent = state.agent
    config = Jido.AI.get_strategy_config(agent)

    assert config.system_prompt == "Use the clock when asked."
    assert config.request_policy == :reject
    assert config.tool_max_retries == 0
    assert Enum.map(config.tools, & &1.name()) == ["get_current_time"]
  end

  test "executes successive host-action rounds through Jido's loop" do
    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: "act-tool-loop", tools: [TestAgentTool], maximum_result_bytes: 4_096}
      )

    agent_server = start_agent_server("act-tool-loop")

    assert :ok =
             AgentFactory.configure(
               agent_server,
               system_prompt: "Use the clock twice.",
               tools: [TestAgentTool]
             )

    script =
      expect_react do
        user("check twice")
        call("test_agent_tool", %{"value" => "one"}, id: "tool-one")
        call("test_agent_tool", %{"value" => "two"}, id: "tool-two")
        answer("Both checks completed.")
      end

    options =
      script
      |> Jido.AI.Test.react_opts()
      |> Keyword.put(:tool_context, %{
        vxpipe_tool_context: tool_context(),
        vxpipe_tool_dispatcher: dispatcher
      })

    assert {:ok, %{request: request, events: events}} =
             Agent.ask_stream(agent_server, "check twice", options)

    events = Enum.to_list(events)

    assert {:ok, "Both checks completed."} = Agent.await(request)

    assert ["tool-one", "tool-two"] ==
             for(%Event{kind: :tool_started, tool_call_id: id} <- events, do: id)

    assert ["test_agent_tool", "test_agent_tool"] ==
             for(%Event{kind: :tool_completed, tool_name: name} <- events, do: name)

    assert Enum.all?(
             for(%Event{kind: :tool_completed, data: data} <- events, do: data),
             fn data ->
               data.attempts == 1 and match?({:ok, %{"value" => _value}, []}, data.result)
             end
           )

    assert [%Event{kind: :request_completed, data: %{result: "Both checks completed."}}] =
             Enum.filter(events, &(&1.kind == :request_completed))
  end

  defp tool_context do
    %Context{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "rinc-test",
      agent_participant_id: "agent-test",
      source_participant_id: "caller-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "correlation-test"
    }
  end

  defp start_agent_server(id) do
    start_supervised!(
      {Jido.AgentServer,
       agent: Agent, id: id, jido: Vxpipe.CallEngine.Jido, register_global: false}
    )
  end
end
