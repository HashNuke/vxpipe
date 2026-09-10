defmodule Vxpipe.CallEngine.AgentRuntime.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, Session}
  alias Vxpipe.CallEngine.AgentRuntime.{Coordinator, PendingContextSource}
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationSupervisor}

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
         completion_target: coordinator,
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

    %{coordinator: coordinator}
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
