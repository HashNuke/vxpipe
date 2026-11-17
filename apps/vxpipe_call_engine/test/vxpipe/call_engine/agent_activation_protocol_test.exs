defmodule Vxpipe.CallEngine.AgentActivationProtocolTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelContextCompactor, Protocol}
  alias Vxpipe.CallEngine.AgentActivation.RuntimeGraph
  alias Vxpipe.CallEngine.Usage.ProviderContext

  test "publication instructions never make malformed explicit compactor state valid" do
    {:ok, protocol} = Protocol.capture()
    options = options(protocol, {ModelContextCompactor, :invalid})

    assert {:error, :invalid_configuration} =
             RuntimeGraph.children(Keyword.delete(options, :agent_protocol))

    assert {:error, :invalid_configuration} = RuntimeGraph.children(options)
  end

  test "publication summary instructions are pinned by the runtime owner" do
    {:ok, protocol} = Protocol.capture()
    text = "Publication-specific summary instructions"

    prompt = %{
      "text" => text,
      "revision" => :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    }

    protocol = put_in(protocol, ["prompts", "conversation_summary"], prompt)

    state = %{
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()}
    }

    activation =
      start_supervised!(
        {Vxpipe.CallEngine.AgentActivationSupervisor,
         options(protocol, {ModelContextCompactor, state})}
      )

    %{session: session} = Vxpipe.CallEngine.AgentActivationSupervisor.children(activation)
    config = :sys.get_state(session).configuration
    assert config.reply_protocol == :mode_message_v1
    assert {ModelContextCompactor, pinned} = config.context_preparation.compactor
    assert pinned.summary_prompt.text == text
    assert config.instructions =~ protocol["prompts"]["llm_dialogue"]["text"]
  end

  test "an explicit legacy bundle retains its decoder and shared instructions" do
    {:ok, protocol} = Vxpipe.CallEngine.AgentProtocol.capture(:legacy)

    state = %{
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()}
    }

    activation =
      start_supervised!(
        {Vxpipe.CallEngine.AgentActivationSupervisor,
         options(protocol, {ModelContextCompactor, state})}
      )

    %{session: session} = Vxpipe.CallEngine.AgentActivationSupervisor.children(activation)
    config = :sys.get_state(session).configuration
    assert config.reply_protocol == :legacy
    assert config.instructions == protocol["prompts"]["shared"]["text"] <> "\n\nAuthored"
  end

  test "direct activation cannot advertise native idle under a legacy protocol" do
    {:ok, modern} = Vxpipe.CallEngine.AgentProtocol.capture()
    {:ok, legacy} = Vxpipe.CallEngine.AgentProtocol.capture(:legacy)

    state = %{
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()}
    }

    binding = %Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding{
      name: "idle",
      type: :platform,
      conversation_mode: :non_blocking,
      action: Vxpipe.CallEngine.Tool.Idle,
      remote: nil
    }

    modern_options =
      options(modern, {ModelContextCompactor, state}) |> Keyword.put(:tools, %{"idle" => binding})

    assert {:ok, _children} = RuntimeGraph.children(modern_options)

    for protocol <- [nil, legacy] do
      assert {:error, :invalid_configuration} =
               RuntimeGraph.children(Keyword.put(modern_options, :agent_protocol, protocol))
    end
  end

  defp options(protocol, compactor) do
    {:ok, usage} =
      ProviderContext.new(name: "test", integration_id: "test-model", model: "test:scripted")

    [
      activation_id: "protocol-#{System.unique_integer([:positive])}",
      agent_participant_id: "agent",
      call_id: "call",
      owner: self(),
      system_prompt: "Authored",
      tools: %{},
      variable_binding: nil,
      history_mode: :host_settled,
      agent_protocol: protocol,
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      provider: :test,
      usage_provider: usage,
      tool_invocation_timeout_ms: 1000,
      maximum_completed_requests: 4,
      maximum_tool_invocations: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4096,
      request_timeout_ms: 1000,
      context_compaction: [
        enabled: true,
        context_window_tokens: 1000,
        output_reserve_tokens: 100,
        compactor: compactor
      ]
    ]
  end
end
