defmodule Vxpipe.CallEngine.AgentActivationPromptTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.Usage.ProviderContext

  test "each activation reads current shared policy and keeps it through child restarts" do
    original_ebin = Application.app_dir(:vxpipe_agent_runtime, "ebin")

    directory =
      Path.join(System.tmp_dir!(), "vxpipe-review-restart-#{System.unique_integer([:positive])}")

    app_directory = Path.join(directory, "vxpipe_agent_runtime-0.1.0")
    ebin = Path.join(app_directory, "ebin")
    prompts = Path.join(app_directory, "priv/prompts")
    File.mkdir_p!(app_directory)
    File.cp_r!(original_ebin, ebin)
    File.mkdir_p!(prompts)
    summary = Path.join(prompts, "conversation-summary-system.md")
    shared = Path.join(prompts, "agent-system.md")
    File.write!(summary, "Original summary instructions")
    File.write!(shared, "Original shared instructions")
    assert true = :code.replace_path(:vxpipe_agent_runtime, String.to_charlist(ebin))

    on_exit(fn ->
      :code.replace_path(:vxpipe_agent_runtime, String.to_charlist(original_ebin))
      File.rm_rf!(directory)
    end)

    {:ok, usage_provider} =
      ProviderContext.new(name: "test", integration_id: "test-model", model: "test:scripted")

    options = [
      runtime: :agent_runtime,
      activation_id: "review-prompt-#{System.unique_integer([:positive])}",
      agent_participant_id: "agent-test",
      call_id: "call-test",
      owner: self(),
      system_prompt: "Authored instructions",
      tools: %{},
      variable_binding: nil,
      history_mode: :host_settled,
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      provider: :test,
      usage_provider: usage_provider,
      tool_invocation_timeout_ms: 1000,
      maximum_completed_requests: 4,
      maximum_tool_invocations: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4096,
      request_timeout_ms: 1000,
      context_compaction: [enabled: true, context_window_tokens: 1000, output_reserve_tokens: 100]
    ]

    activation = start_supervised!({AgentActivationSupervisor, options})
    first = AgentActivationSupervisor.children(activation)
    initial = :sys.get_state(first.session).configuration
    assert initial.instructions == "Original shared instructions\n\nAuthored instructions"
    {_, initial_compactor} = initial.context_preparation.compactor
    assert initial_compactor.summary_prompt.text == "Original summary instructions"

    File.write!(summary, "Edited summary instructions")
    File.write!(shared, "Edited shared instructions")
    monitors = Enum.map(first, fn {_, pid} -> {pid, Process.monitor(pid)} end)
    Process.exit(first.session, :kill)

    for {pid, monitor} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2000
    end

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)
    refute second.session == first.session
    restarted = :sys.get_state(second.session).configuration
    assert restarted.instructions == initial.instructions
    {_, restarted_compactor} = restarted.context_preparation.compactor
    assert restarted_compactor.summary_prompt.text == initial_compactor.summary_prompt.text

    next_options = Keyword.update!(options, :activation_id, &(&1 <> "-next"))

    next =
      start_supervised!(
        Supervisor.child_spec({AgentActivationSupervisor, next_options}, id: :next_activation)
      )

    next_session = AgentActivationSupervisor.children(next).session

    assert :sys.get_state(next_session).configuration.instructions ==
             "Edited shared instructions\n\nAuthored instructions"

    File.rm!(shared)

    assert {:error, :prompt_unavailable} =
             Vxpipe.AgentRuntime.Protocol.instructions(nil, "Authored instructions", :llm)
  end
end
