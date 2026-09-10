defmodule Vxpipe.CallEngine.AgentRuntime.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, PendingInvocation, Session}
  alias Vxpipe.CallEngine.AgentRuntime.{Coordinator, PendingContextSource}
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.TestSubmittedInlineTool

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_inline_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_inline_tool_observer)
    end)
  end

  test "projects a streamed Agent Runtime response through the existing capability contract" do
    runtime = start_runtime()
    command = command("streamed-runtime", "How are you?")

    assert :ok = Coordinator.respond(runtime.coordinator, command)

    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).content == "How are you?"

    send(provider, {:test_agent_runtime_delta, "I am well. Still "})

    assert_receive {:vxpipe_capability_text, coordinator, ^command, "I am well."}
    assert coordinator == runtime.coordinator

    send(provider, {:test_agent_runtime_delta, "working!"})
    assert {:ok, response} = ModelResponse.new(text: "I am well. Still working!")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command, "Still working!"}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
    refute_receive {:vxpipe_capability_text, ^coordinator, ^command, _duplicate}
  end

  test "cancels a rejected stream before advancing queued caller work" do
    runtime = start_runtime(maximum_output_bytes: 5, session_maximum_output_bytes: 4_096)
    rejected = command("rejected-runtime", "First")
    queued = command("queued-runtime", "Second")

    assert :ok = Coordinator.respond(runtime.coordinator, rejected)
    assert_receive {:test_agent_runtime_stream, first_provider, _request}
    assert :ok = Coordinator.respond(runtime.coordinator, queued)

    send(first_provider, {:test_agent_runtime_delta, "overflow"})

    assert_receive {:vxpipe_capability_failed, coordinator, ^rejected, :invalid_response}
    assert coordinator == runtime.coordinator
    assert_receive {:test_agent_runtime_stream, second_provider, second_request}
    assert List.last(second_request.messages).content == "Second"

    assert {:ok, response} = ModelResponse.new(text: "Done.")
    send(second_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, ^coordinator, ^queued, "Done."}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}
  end

  test "holds caller turns outside the model while a blocking invocation is unconsumed" do
    runtime = start_runtime(completion_target: self())
    command = command("blocked-runtime", "Can we discuss something else?")

    assert {:accepted, :blocking} = submit_invocation(runtime, :blocking, "blocking-call")
    assert_receive {:submitted_inline_tool_started, execution, "blocking-call"}

    assert :ok = Coordinator.respond(runtime.coordinator, command)

    assert_receive {:vxpipe_capability_text, coordinator, ^command,
                    "Please hold while I finish the current request."}

    assert coordinator == runtime.coordinator
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
    refute_receive {:test_agent_runtime_stream, _provider, _request}

    send(execution, :release_submitted_inline_tool)
    assert_receive {:vxpipe_tool_completion_available, registry, "blocking-call"}
    assert registry == GenServer.whereis(runtime.registry)

    terminal_command = command("blocked-terminal", "Is it ready now?")
    assert :ok = Coordinator.respond(runtime.coordinator, terminal_command)

    assert_receive {:vxpipe_capability_text, ^coordinator, ^terminal_command,
                    "Please hold while I finish the current request."}

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^terminal_command}

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = continuation}

    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).origin == :engine
    refute List.last(request.messages).content =~ terminal_command.content

    assert {:ok, response} = ModelResponse.new(text: "The request completed.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^continuation}
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)
  end

  test "admits unrelated caller turns with non-blocking pending context" do
    runtime = start_runtime()
    command = command("non-blocking-runtime", "What are the usage rules?")

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "non-blocking-call")

    assert_receive {:submitted_inline_tool_started, _execution, "non-blocking-call"}
    assert :ok = Coordinator.respond(runtime.coordinator, command)

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [
             %PendingInvocation{
               invocation_id: "non-blocking-call",
               conversation_mode: :non_blocking,
               status: :running
             }
           ] = request.pending_invocations

    assert {:ok, response} = ModelResponse.new(text: "The usual rules apply.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, coordinator, ^command, "The usual rules apply."}
    assert coordinator == runtime.coordinator
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
  end

  test "holds a later caller turn while the blocking acknowledgement request is active" do
    runtime = start_runtime()
    acknowledgement = command("blocking-acknowledgement", "Start checking")
    later = command("blocking-later", "Can we discuss something else?")

    assert :ok = Coordinator.respond(runtime.coordinator, acknowledgement)
    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:accepted, :blocking} =
             submit_invocation(runtime, :blocking, "blocking-acknowledgement-call")

    assert_receive {:submitted_inline_tool_started, _execution, "blocking-acknowledgement-call"}
    assert :ok = Coordinator.respond(runtime.coordinator, later)

    assert_receive {:vxpipe_capability_text, coordinator, ^later,
                    "Please hold while I finish the current request."}

    assert coordinator == runtime.coordinator
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^later}

    assert {:ok, response} = ModelResponse.new(text: "I am checking now.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^acknowledgement}
  end

  test "consumes a completed invocation before queued caller work" do
    runtime = start_runtime(completion_target: self())
    current = command("completion-current", "Start the request")
    queued = command("completion-queued", "What happened?")

    assert :ok = Coordinator.respond(runtime.coordinator, current)
    assert_receive {:test_agent_runtime_stream, current_provider, _request}

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "completion-call")

    assert_receive {:submitted_inline_tool_started, execution, "completion-call"}
    assert :ok = Coordinator.respond(runtime.coordinator, queued)
    send(execution, :release_submitted_inline_tool)

    assert_receive {:vxpipe_tool_completion_available, registry, "completion-call"}
    send(runtime.coordinator, {:vxpipe_tool_completion_available, registry, "completion-call"})

    assert {:ok, response} = ModelResponse.new(text: "I started it.")
    send(current_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text_complete, coordinator, ^current}
    assert coordinator == runtime.coordinator

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = continuation}

    assert continuation.tool_call_id == "completion-call"
    assert continuation.source_command_id == "command-completion-call"

    assert_receive {:test_agent_runtime_stream, continuation_provider, continuation_request}
    continuation_message = List.last(continuation_request.messages)
    assert continuation_message.origin == :engine
    assert continuation_message.content =~ ~s("invocation_id":"completion-call")
    assert continuation_message.content =~ ~s("type":"tool_invocation_completion")
    refute continuation_message.content =~ queued.content

    assert {:ok, response} = ModelResponse.new(text: "The request completed.")
    send(continuation_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, ^coordinator, ^continuation,
                    "The request completed."}

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^continuation}

    assert_receive {:test_agent_runtime_stream, queued_provider, queued_request}
    assert List.last(queued_request.messages).content == queued.content
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)

    assert {:ok, response} = ModelResponse.new(text: "Everything completed.")
    send(queued_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}
  end

  test "leases an already completed non-blocking invocation before a racing caller" do
    runtime = start_runtime(completion_target: self())
    caller = command("completion-race", "Did anything finish?")

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "completion-race-call")

    assert_receive {:submitted_inline_tool_started, execution, "completion-race-call"}
    send(execution, :release_submitted_inline_tool)
    assert_receive {:vxpipe_tool_completion_available, _registry, "completion-race-call"}

    assert :ok = Coordinator.respond(runtime.coordinator, caller)

    assert_receive {:vxpipe_capability_continuation_started, coordinator,
                    %ContinueAgent{} = continuation}

    assert continuation.tool_call_id == "completion-race-call"
    assert_receive {:test_agent_runtime_stream, continuation_provider, _request}

    assert {:ok, response} = ModelResponse.new(text: "The tool finished.")
    send(continuation_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^continuation}

    assert_receive {:test_agent_runtime_stream, caller_provider, caller_request}
    assert List.last(caller_request.messages).content == caller.content

    assert {:ok, response} = ModelResponse.new(text: "Yes.")
    send(caller_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^caller}
  end

  test "releases an uncommitted completion lease and fails closed" do
    runtime = start_runtime(completion_target: self())

    assert {:accepted, :blocking} =
             submit_invocation(runtime, :blocking, "failed-continuation-call")

    assert_receive {:submitted_inline_tool_started, execution, "failed-continuation-call"}
    send(execution, :release_submitted_inline_tool)

    assert_receive {:vxpipe_tool_completion_available, registry, "failed-continuation-call"}
    monitor = Process.monitor(runtime.coordinator)

    send(
      runtime.coordinator,
      {:vxpipe_tool_completion_available, registry, "failed-continuation-call"}
    )

    assert_receive {:vxpipe_capability_continuation_started, coordinator,
                    %ContinueAgent{} = continuation}

    assert_receive {:test_agent_runtime_stream, provider, _request}
    send(provider, {:test_agent_runtime_response, {:error, :provider_unavailable}})

    assert_receive {:vxpipe_capability_failed, ^coordinator, ^continuation, :provider_unavailable}

    assert_receive {:DOWN, ^monitor, :process, ^coordinator, :completion_continuation_failed}

    assert {:ok,
            [
              %Vxpipe.CallEngine.Tool.InvocationStatus{
                invocation_id: "failed-continuation-call",
                status: :terminal_queued
              }
            ]} = InvocationRegistry.snapshot(runtime.registry)
  end

  defp start_runtime(options \\ []) do
    suffix = System.unique_integer([:positive])
    activation_id = "act-runtime-coordinator-#{suffix}"
    session_name = {:global, {:test_runtime_session, suffix}}
    request_supervisor_name = {:global, {:test_runtime_request_supervisor, suffix}}
    registry_name = {:global, {:test_runtime_invocation_registry, suffix}}

    _request_supervisor =
      start_supervised!({Task.Supervisor, name: request_supervisor_name})

    coordinator =
      start_supervised!(
        {Coordinator,
         activation_id: activation_id,
         agent_participant_id: "participant-agent",
         session: session_name,
         invocation_registry: registry_name,
         request_supervisor: request_supervisor_name,
         owner: self(),
         provider: :local_fixture,
         maximum_output_bytes: Keyword.get(options, :maximum_output_bytes, 4_096),
         maximum_pending_requests: 2}
      )

    invocation_supervisor =
      start_supervised!({InvocationSupervisor, activation_id: activation_id, maximum_children: 2})

    _registry =
      start_supervised!(
        {InvocationRegistry,
         activation_id: activation_id,
         name: registry_name,
         invocation_supervisor: invocation_supervisor,
         completion_target: Keyword.get(options, :completion_target, coordinator),
         maximum_invocations: 2,
         maximum_consumed_invocations: 4,
         invocation_timeout_ms: 1_000,
         maximum_result_bytes: 4_096}
      )

    _session =
      start_supervised!(
        {Session,
         name: session_name,
         instructions: "Answer briefly.",
         model_provider: TestAgentRuntimeModelProvider,
         model: %{owner: self()},
         tools: [],
         executor: nil,
         pending_context_source: {PendingContextSource, registry_name},
         event_destination: coordinator,
         maximum_output_bytes: Keyword.get(options, :session_maximum_output_bytes, 4_096),
         request_timeout_ms: 1_000}
      )

    %{coordinator: coordinator, registry: registry_name}
  end

  defp submit_invocation(runtime, conversation_mode, invocation_id) do
    resolved = %ToolBinding{
      name: "submitted_inline_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedInlineTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)

    InvocationRegistry.submit(
      runtime.registry,
      binding,
      %{"value" => invocation_id},
      invocation_context(invocation_id),
      invocation_id
    )
  end

  defp invocation_context(invocation_id) do
    %Context{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "incarnation-demo",
      agent_participant_id: "participant-agent",
      source_participant_id: "participant-caller",
      connection_id: "connection-caller",
      command_id: "command-#{invocation_id}",
      correlation_id: "turn-#{invocation_id}",
      agent_request_id: "request-#{invocation_id}",
      tool_call_id: nil,
      audio_response: true
    }
  end

  defp command(seed, content) do
    assert {:ok, command} =
             SendText.new(
               id: "command-#{seed}",
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
               room_id: "room-demo",
               incarnation_id: "incarnation-demo",
               participant_id: "participant-caller",
               connection_id: "connection-caller",
               correlation_id: "turn-#{seed}",
               content: content,
               run_immediately: true,
               audio_response: true,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end
end
