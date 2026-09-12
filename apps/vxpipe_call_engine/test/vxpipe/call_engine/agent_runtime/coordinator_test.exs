defmodule Vxpipe.CallEngine.AgentRuntime.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Event,
    ModelResponse,
    PendingInvocation,
    Session,
    ToolCall,
    ToolDescriptor
  }

  alias Vxpipe.CallEngine.AgentRuntime.{
    Coordinator,
    InvocationExecutor,
    PendingContextSource
  }

  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.TestSubmittedHostTool
  alias Vxpipe.CallEngine.Usage.{Observation, ProviderContext}

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

  @model_first_token_event [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop_event [:vxpipe, :call_engine, :model, :request, :stop]
  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
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

  test "hands a completed model round to the room as private typed usage" do
    runtime = start_runtime()
    command = command("usage-runtime", "Count this model round")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, response} =
             ModelResponse.new(
               text: "Counted.",
               usage: %{input_tokens: 9, output_tokens: 3, total_tokens: 12},
               provider_metadata: %{
                 model: "fixture:usage-model",
                 request_id: "provider-model-request-1",
                 response_id: "provider-model-response-1"
               }
             )

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_usage_observations, coordinator, observations}
    assert coordinator == runtime.coordinator
    assert length(observations) == 3
    assert [attempt_id] = observations |> Enum.map(& &1.attempt_id) |> Enum.uniq()
    assert String.starts_with?(attempt_id, "matt_")

    assert Enum.all?(observations, fn
             %Observation{
               tenant_id: "tenant-demo",
               call_id: "call-demo",
               capability: :model_inference,
               outcome: :succeeded
             } = observation ->
               observation.attempt_id == attempt_id and
                 observation.provider.name == "fixture" and
                 observation.provider.integration_id == "test-model" and
                 observation.provider.request_id == "provider-model-request-1" and
                 observation.provider.operation_id == "provider-model-response-1" and
                 observation.attribution.activation_id == runtime.activation_id and
                 observation.attribution.turn_id == command.correlation_id

             _other ->
               false
           end)

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
  end

  test "hands compaction usage to the room as a separate model attempt" do
    runtime = start_runtime()
    command = command("compaction-usage", "Make room before this model round")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, request}

    send(
      runtime.coordinator,
      {:agent_runtime_event,
       Event.new(:context_compaction_usage, request.correlation, %{
         outcome: :failed,
         usage: %{input_tokens: 25, output_tokens: 7, total_tokens: 32},
         provider_metadata: %{request_id: "provider-compaction-request"}
       })}
    )

    assert_receive {:vxpipe_usage_observations, coordinator, compaction_observations}
    assert coordinator == runtime.coordinator

    assert Enum.map(compaction_observations, & &1.measurement.component) == [
             "context_compaction_input_tokens",
             "context_compaction_output_tokens",
             "context_compaction_total_tokens"
           ]

    assert [compaction_attempt] =
             compaction_observations |> Enum.map(& &1.attempt_id) |> Enum.uniq()

    assert Enum.all?(compaction_observations, fn observation ->
             observation.attribution.turn_id == command.correlation_id and
               observation.provider.request_id == "provider-compaction-request" and
               observation.outcome == :failed
           end)

    assert {:ok, response} =
             ModelResponse.new(text: "Ready.", usage: %{total_tokens: 11})

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_usage_observations, ^coordinator, conversation_observations}
    refute hd(conversation_observations).attempt_id == compaction_attempt
    assert hd(conversation_observations).measurement.component == "total_tokens"
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
  end

  test "keeps intermediate tool and final model rounds as distinct usage attempts" do
    descriptor = runtime_tool_descriptor(:non_blocking)
    runtime = start_runtime(tools: [descriptor], executor: InvocationExecutor)
    command = command("multi-round-usage", "Start the background operation")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, first_provider, _request}

    assert {:ok, tool_call} =
             ToolCall.new(
               id: "usage-tool-call",
               name: "submitted_host_tool",
               arguments: %{"value" => "usage-tool"}
             )

    assert {:ok, first_response} =
             ModelResponse.new(
               text: "I am starting it.",
               tool_calls: [tool_call],
               usage: %{input_tokens: 10, output_tokens: 2, total_tokens: 12},
               provider_metadata: %{request_id: "provider-round-1"}
             )

    send(first_provider, {:test_agent_runtime_response, {:ok, first_response}})

    assert_receive {:vxpipe_usage_observations, coordinator, first_observations}
    assert_receive {:submitted_host_tool_started, execution, "usage-tool"}
    assert_receive {:test_agent_runtime_stream, second_provider, _request}

    assert {:ok, second_response} =
             ModelResponse.new(
               text: "It is running.",
               usage: %{input_tokens: 20, output_tokens: 3, total_tokens: 23},
               provider_metadata: %{request_id: "provider-round-2"}
             )

    send(second_provider, {:test_agent_runtime_response, {:ok, second_response}})

    assert_receive {:vxpipe_usage_observations, ^coordinator, second_observations}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}

    assert [first_attempt] = first_observations |> Enum.map(& &1.attempt_id) |> Enum.uniq()
    assert [second_attempt] = second_observations |> Enum.map(& &1.attempt_id) |> Enum.uniq()
    refute first_attempt == second_attempt
    assert hd(first_observations).provider.request_id == "provider-round-1"
    assert hd(second_observations).provider.request_id == "provider-round-2"

    send(execution, :release_submitted_host_tool)
  end

  test "retains a failed provider attempt without inventing usage" do
    runtime = start_runtime()
    command = command("failed-model-usage", "Try this provider request")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    send(provider, {:test_agent_runtime_response, {:error, :provider_unavailable}})

    assert_receive {:vxpipe_usage_observations, coordinator, [observation]}
    assert coordinator == runtime.coordinator
    assert observation.capability == :model_inference
    assert observation.outcome == :failed
    assert observation.measurement == nil
    assert String.starts_with?(observation.attempt_id, "matt_")
    assert observation.attribution.turn_id == command.correlation_id
    assert_receive {:vxpipe_capability_failed, ^coordinator, ^command, :provider_unavailable}
  end

  test "retains a cancelled in-flight provider attempt without publishing stale output" do
    runtime = start_runtime()
    command = command("cancelled-model-usage", "Stop this provider request")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    provider_monitor = Process.monitor(provider)

    assert {:ok, [^command]} = Coordinator.interrupt(runtime.coordinator, [])
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}

    assert_receive {:vxpipe_usage_observations, coordinator, [observation]}
    assert coordinator == runtime.coordinator
    assert observation.capability == :model_inference
    assert observation.outcome == :cancelled
    assert observation.measurement == nil
    assert String.starts_with?(observation.attempt_id, "matt_")
    assert observation.attribution.turn_id == command.correlation_id
    refute_receive {:vxpipe_capability_text, ^coordinator, ^command, _text}
  end

  test "reports payload-free first output and successful model telemetry once" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    runtime = start_runtime(provider: :req_llm)
    command = command("telemetry-success", "private-model-input")
    sentinel = "private-model-output"

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    send(provider, {:test_agent_runtime_delta, sentinel})

    assert_receive {:telemetry_event, @model_first_token_event, %{duration: first_duration},
                    %{provider: :req_llm} = first_metadata}

    assert is_integer(first_duration)
    assert first_duration >= 0
    refute inspect(first_metadata) =~ sentinel

    assert {:ok, response} = ModelResponse.new(text: sentinel)
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: total_duration},
                    %{provider: :req_llm, outcome: :ok, first_output: :observed} = stop_metadata}

    assert total_duration >= first_duration
    refute inspect(stop_metadata) =~ sentinel
    refute_receive {:telemetry_event, @model_first_token_event, _, _}
    refute_receive {:telemetry_event, @provider_failure_event, _, _}
  end

  test "reports a safe unavailable outcome for an arbitrary provider failure" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    runtime = start_runtime(provider: :req_llm)
    command = command("telemetry-failure", "private-model-input")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    send(provider, {:test_agent_runtime_response, {:error, :private_provider_reason}})

    assert_receive {:vxpipe_capability_failed, coordinator, ^command, :provider_unavailable}
    assert coordinator == runtime.coordinator

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: duration},
                    %{provider: :req_llm, outcome: :unavailable, first_output: :missing}}

    assert is_integer(duration)
    assert duration >= 0

    assert_receive {:telemetry_event, @provider_failure_event, %{count: 1},
                    %{capability: :model, provider: :req_llm, category: :unavailable}}

    refute_receive {:telemetry_event, @model_first_token_event, _, _}

    replacement = command("after-telemetry-failure", "Try again")
    assert :ok = Coordinator.respond(coordinator, replacement)
    assert_receive {:test_agent_runtime_stream, replacement_provider, replacement_request}
    assert List.last(replacement_request.messages).content == replacement.content

    assert {:ok, response} = ModelResponse.new(text: "Recovered.")
    send(replacement_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}
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

  test "bounds the caller queue and advances it after the active request deadline" do
    runtime = start_runtime(maximum_pending_requests: 1, request_timeout_ms: 250)
    timed_out = command("deadline-runtime", "Take too long")
    queued = command("deadline-queued", "Continue")
    rejected = command("deadline-rejected", "Too many")

    assert :ok = Coordinator.respond(runtime.coordinator, timed_out)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    provider_monitor = Process.monitor(provider)

    assert :ok = Coordinator.respond(runtime.coordinator, queued)
    assert {:error, :queue_full} = Coordinator.respond(runtime.coordinator, rejected)

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}, 1_000

    assert_receive {:vxpipe_capability_failed, coordinator, ^timed_out, :provider_timeout},
                   1_000

    assert coordinator == runtime.coordinator
    assert_receive {:test_agent_runtime_stream, queued_provider, queued_request}, 1_000
    assert List.last(queued_request.messages).content == queued.content

    assert {:ok, response} = ModelResponse.new(text: "Continued.")
    send(queued_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}
  end

  test "holds caller turns outside the model while a blocking invocation is unconsumed" do
    runtime = start_runtime(completion_target: self())
    command = command("blocked-runtime", "Can we discuss something else?")

    assert {:accepted, :blocking} = submit_invocation(runtime, :blocking, "blocking-call")
    assert_receive {:submitted_host_tool_started, execution, "blocking-call"}

    assert :ok = Coordinator.respond(runtime.coordinator, command)

    assert_receive {:vxpipe_capability_text, coordinator, ^command,
                    "Please hold while I finish the current request."}

    assert coordinator == runtime.coordinator
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
    refute_receive {:test_agent_runtime_stream, _provider, _request}

    send(execution, :release_submitted_host_tool)
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

    assert_receive {:submitted_host_tool_started, _execution, "non-blocking-call"}
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

    assert_receive {:submitted_host_tool_started, _execution, "blocking-acknowledgement-call"}
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

    assert_receive {:submitted_host_tool_started, execution, "completion-call"}
    assert :ok = Coordinator.respond(runtime.coordinator, queued)
    send(execution, :release_submitted_host_tool)

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

    assert_receive {:submitted_host_tool_started, execution, "completion-race-call"}
    send(execution, :release_submitted_host_tool)
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

  test "serializes independently completed invocations once with their original identities" do
    runtime = start_runtime()

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "completion-first")

    assert_receive {:submitted_host_tool_started, first_execution, "completion-first"}

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "completion-second")

    assert_receive {:submitted_host_tool_started, second_execution, "completion-second"}

    send(second_execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_capability_continuation_started, coordinator,
                    %ContinueAgent{} = second_continuation}

    assert coordinator == runtime.coordinator
    assert second_continuation.tool_call_id == "completion-second"
    assert_receive {:test_agent_runtime_stream, second_provider, second_request}
    assert List.last(second_request.messages).content =~ ~s("invocation_id":"completion-second")

    send(first_execution, :release_submitted_host_tool)
    refute_receive {:vxpipe_capability_continuation_started, ^coordinator, _while_busy}

    assert {:ok, response} = ModelResponse.new(text: "The second request completed.")
    send(second_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^second_continuation}

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = first_continuation}

    assert first_continuation.tool_call_id == "completion-first"
    assert_receive {:test_agent_runtime_stream, first_provider, first_request}
    assert List.last(first_request.messages).content =~ ~s("invocation_id":"completion-first")

    assert {:ok, response} = ModelResponse.new(text: "The first request completed.")
    send(first_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^first_continuation}
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)
    refute_receive {:vxpipe_capability_continuation_started, ^coordinator, _duplicate}
  end

  test "releases an uncommitted completion lease and fails closed" do
    runtime = start_runtime(completion_target: self())

    assert {:accepted, :blocking} =
             submit_invocation(runtime, :blocking, "failed-continuation-call")

    assert_receive {:submitted_host_tool_started, execution, "failed-continuation-call"}
    send(execution, :release_submitted_host_tool)

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

  test "interrupts current and queued callers, discards selected completed history, and accepts replacement" do
    runtime = start_runtime()
    completed = command("interrupt-completed", "old topic")

    assert :ok = Coordinator.respond(runtime.coordinator, completed)
    assert_receive {:test_agent_runtime_stream, completed_provider, _request}
    assert {:ok, response} = ModelResponse.new(text: "old answer")
    send(completed_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, coordinator, ^completed}
    assert coordinator == runtime.coordinator

    current = command("interrupt-current", "keep talking")
    queued = command("interrupt-queued", "wait for me")
    assert :ok = Coordinator.respond(coordinator, current)
    assert_receive {:test_agent_runtime_stream, current_provider, _request}
    current_monitor = Process.monitor(current_provider)
    assert :ok = Coordinator.respond(coordinator, queued)

    completed_identity = {completed.connection_id, completed.correlation_id, completed.id}
    assert {:ok, [^current, ^queued]} = Coordinator.interrupt(coordinator, [completed_identity])
    assert_receive {:DOWN, ^current_monitor, :process, ^current_provider, _reason}

    replacement = command("interrupt-replacement", "new topic")
    assert :ok = Coordinator.respond(coordinator, replacement)
    assert_receive {:test_agent_runtime_stream, replacement_provider, replacement_request}

    assert Enum.map(replacement_request.messages, & &1.role) == [:system, :user]
    assert List.last(replacement_request.messages).content == replacement.content
    refute Enum.any?(replacement_request.messages, &(&1.content == completed.content))
    refute Enum.any?(replacement_request.messages, &(&1.content == "old answer"))

    assert {:ok, response} = ModelResponse.new(text: "new answer")
    send(replacement_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}
  end

  test "reports caller interruption as cancelled without a provider failure" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    runtime = start_runtime(provider: :req_llm)
    command = command("telemetry-interruption", "Stop this request")

    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, _provider, _request}
    assert {:ok, [^command]} = Coordinator.interrupt(runtime.coordinator, [])

    assert_receive {:vxpipe_capability_failed, coordinator, ^command, :interrupted}
    assert coordinator == runtime.coordinator

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: duration},
                    %{provider: :req_llm, outcome: :cancelled, first_output: :missing}}

    assert is_integer(duration)
    assert duration >= 0
    refute_receive {:telemetry_event, @model_first_token_event, _, _}
    refute_receive {:telemetry_event, @provider_failure_event, _, _}
  end

  test "interrupting model work does not cancel a separately supervised tool worker" do
    runtime = start_runtime(completion_target: self())
    current = command("interrupt-with-tool", "keep talking")

    assert :ok = Coordinator.respond(runtime.coordinator, current)
    assert_receive {:test_agent_runtime_stream, _provider, _request}

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "interrupt-surviving-call")

    assert_receive {:submitted_host_tool_started, execution, "interrupt-surviving-call"}

    assert {:ok, [^current]} = Coordinator.interrupt(runtime.coordinator, [])

    assert {:ok,
            [
              %Vxpipe.CallEngine.Tool.InvocationStatus{
                invocation_id: "interrupt-surviving-call",
                status: :running
              }
            ]} = InvocationRegistry.snapshot(runtime.registry)

    send(execution, :release_submitted_host_tool)
    assert_receive {:vxpipe_tool_completion_available, _registry, "interrupt-surviving-call"}
  end

  test "interrupts and retries an uncommitted non-blocking completion after replacement caller work" do
    runtime = start_runtime()

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "interrupted-completion-call")

    assert_receive {:submitted_host_tool_started, execution, "interrupted-completion-call"}
    send(execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_capability_continuation_started, coordinator,
                    %ContinueAgent{} = interrupted_continuation}

    assert coordinator == runtime.coordinator
    assert_receive {:test_agent_runtime_stream, interrupted_provider, _request}
    interrupted_monitor = Process.monitor(interrupted_provider)

    assert {:ok, []} = Coordinator.interrupt(coordinator, [])
    assert_receive {:DOWN, ^interrupted_monitor, :process, ^interrupted_provider, _reason}

    assert {:ok,
            [
              %Vxpipe.CallEngine.Tool.InvocationStatus{
                invocation_id: "interrupted-completion-call",
                status: :terminal_queued
              }
            ]} = InvocationRegistry.snapshot(runtime.registry)

    replacement = command("replacement-before-completion-retry", "let me add something")
    assert :ok = Coordinator.respond(coordinator, replacement)
    assert_receive {:test_agent_runtime_stream, replacement_provider, replacement_request}
    assert List.last(replacement_request.messages).content == replacement.content

    assert {:ok, response} = ModelResponse.new(text: "Go ahead.")
    send(replacement_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = retried_continuation}

    assert retried_continuation.tool_call_id == interrupted_continuation.tool_call_id
    assert_receive {:test_agent_runtime_stream, retried_provider, _request}

    assert {:ok, response} = ModelResponse.new(text: "The request completed.")
    send(retried_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^retried_continuation}
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)
  end

  test "holds a replacement while retrying an interrupted blocking completion" do
    runtime = start_runtime()

    assert {:accepted, :blocking} =
             submit_invocation(runtime, :blocking, "interrupted-blocking-completion")

    assert_receive {:submitted_host_tool_started, execution, "interrupted-blocking-completion"}

    send(execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_capability_continuation_started, coordinator,
                    %ContinueAgent{} = interrupted_continuation}

    assert_receive {:test_agent_runtime_stream, _interrupted_provider, _request}
    assert {:ok, []} = Coordinator.interrupt(coordinator, [])

    replacement = command("held-before-completion-retry", "can we continue?")
    assert :ok = Coordinator.respond(coordinator, replacement)

    assert_receive {:vxpipe_capability_text, ^coordinator, ^replacement,
                    "Please hold while I finish the current request."}

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}

    replacement_correlation_id = replacement.correlation_id

    refute_receive {:test_agent_runtime_stream, _caller_provider,
                    %{correlation: %{correlation_id: ^replacement_correlation_id}}}

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = retried_continuation}

    assert retried_continuation.tool_call_id == interrupted_continuation.tool_call_id
    assert_receive {:test_agent_runtime_stream, retried_provider, _request}

    assert {:ok, response} = ModelResponse.new(text: "The request completed.")
    send(retried_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^retried_continuation}
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)
  end

  test "acknowledges an interrupted completion after its nested tool exchange commits" do
    descriptor = runtime_tool_descriptor(:non_blocking)
    runtime = start_runtime(tools: [descriptor], executor: InvocationExecutor)

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "durable-completion-call")

    assert_receive {:submitted_host_tool_started, execution, "durable-completion-call"}
    send(execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_capability_continuation_started, coordinator, %ContinueAgent{}}
    assert_receive {:test_agent_runtime_stream, completion_provider, _request}

    {:ok, nested_call} =
      ToolCall.new(
        id: "nested-tool-call",
        name: "submitted_host_tool",
        arguments: %{"value" => "nested"}
      )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [nested_call])
    send(completion_provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:submitted_host_tool_started, nested_execution, "nested"}
    assert_receive {:test_agent_runtime_stream, _acknowledgement_provider, _request}

    assert {:ok, []} = Coordinator.interrupt(coordinator, [])

    assert {:ok,
            [
              %Vxpipe.CallEngine.Tool.InvocationStatus{
                invocation_id: "nested-tool-call",
                status: :running
              }
            ]} = InvocationRegistry.snapshot(runtime.registry)

    send(nested_execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = nested_continuation}

    assert_receive {:test_agent_runtime_stream, nested_provider, _request}
    assert {:ok, response} = ModelResponse.new(text: "The nested request completed.")
    send(nested_provider, {:test_agent_runtime_response, {:ok, response}})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^nested_continuation}
    assert {:ok, []} = InvocationRegistry.snapshot(runtime.registry)
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
         call_id: "call-demo",
         session: session_name,
         invocation_registry: registry_name,
         request_supervisor: request_supervisor_name,
         owner: self(),
         provider: Keyword.get(options, :provider, :local_fixture),
         usage_provider: usage_provider_context(),
         maximum_output_bytes: Keyword.get(options, :maximum_output_bytes, 4_096),
         maximum_pending_requests: Keyword.get(options, :maximum_pending_requests, 2)}
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
         tools: Keyword.get(options, :tools, []),
         executor: Keyword.get(options, :executor),
         pending_context_source: {PendingContextSource, registry_name},
         event_destination: coordinator,
         maximum_output_bytes: Keyword.get(options, :session_maximum_output_bytes, 4_096),
         request_timeout_ms: Keyword.get(options, :request_timeout_ms, 1_000)}
      )

    %{activation_id: activation_id, coordinator: coordinator, registry: registry_name}
  end

  defp usage_provider_context do
    assert {:ok, provider} =
             ProviderContext.new(
               name: "fixture",
               integration_id: "test-model",
               model: "fixture:default"
             )

    provider
  end

  defp submit_invocation(runtime, conversation_mode, invocation_id) do
    resolved = %ToolBinding{
      name: "submitted_host_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedHostTool,
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

  defp runtime_tool_descriptor(conversation_mode) do
    resolved = %ToolBinding{
      name: "submitted_host_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedHostTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)

    assert {:ok, descriptor} =
             ToolDescriptor.new(
               name: "submitted_host_tool",
               description: "Complete a controlled test operation",
               input_schema: %{
                 "type" => "object",
                 "properties" => %{"value" => %{"type" => "string"}},
                 "required" => ["value"],
                 "additionalProperties" => false
               },
               binding: binding
             )

    descriptor
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

  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  defp attach_telemetry_events(events) do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
