defmodule Vxpipe.CallEngine.AgentRuntime.CoordinatorOverlapTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.Session
  import Vxpipe.CallEngine.TestVoiceToolRoom, only: [reply: 3]
  alias Vxpipe.CallEngine.AgentRuntime.{Coordinator, ModelContextSource}
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.TestAgentRuntimeModelProvider
  alias Vxpipe.CallEngine.TestSubmittedHostTool
  alias Vxpipe.CallEngine.Usage.ProviderContext

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
    end)
  end

  test "starts a leased completion while predecessor output is outstanding and releases in order" do
    runtime = start_runtime(history_mode: :host_settled)
    first = command("overlap-first", "First question")
    assert :ok = Coordinator.respond(runtime.coordinator, first)
    assert_receive {:test_agent_runtime_stream, first_provider, _request}
    reply(first_provider, :speaker, "first answer")
    assert_receive {:vxpipe_capability_text, _, ^first, "first answer"}
    # Predecessor completes in Session but stays outstanding until settle.
    assert_receive {:vxpipe_capability_text_complete, _coordinator, ^first}

    # Make a completion available while predecessor outstanding.
    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "overlap-completion")

    assert_receive {:submitted_host_tool_started, execution, "overlap-completion"}
    send(execution, :release_submitted_host_tool)

    assert_receive {:test_agent_runtime_stream, overlap_provider, overlap_request}, 500
    # Provisional context must describe in-flight audio, not claim it heard.
    assert overlap_request.model_context["in_flight_audio"]["status"] in ["playing", "queued"]

    # Ordered output: nothing for the overlap may escape before predecessor settles.
    refute_received {:vxpipe_capability_text, _, _, "overlap answer"}
    refute_received {:vxpipe_capability_text_complete, _, _}

    reply(overlap_provider, :speaker, "overlap answer")

    # Still withheld after worker returns.
    refute_received {:vxpipe_capability_text, _, _, "overlap answer"}

    assert :ok = Coordinator.settle_output(runtime.coordinator, first, "first answer")
    assert_receive {:vxpipe_capability_text, _, _, "overlap answer"}
  end

  test "caller and idle work wait while a predecessor is outstanding" do
    runtime = start_runtime(history_mode: :host_settled)
    first = command("order-first", "First")
    assert :ok = Coordinator.respond(runtime.coordinator, first)
    assert_receive {:test_agent_runtime_stream, first_provider, _}
    reply(first_provider, :speaker, "first")
    assert_receive {:vxpipe_capability_text, _, ^first, "first"}
    assert_receive {:vxpipe_capability_text_complete, _, ^first}

    queued = command("order-queued", "Second")
    assert :ok = Coordinator.respond(runtime.coordinator, queued)
    refute_received {:test_agent_runtime_stream, _, _}
  end

  test "interruption cancels held overlap without publishing it" do
    runtime = start_runtime(history_mode: :host_settled)
    first = command("interrupt-first", "First")
    assert :ok = Coordinator.respond(runtime.coordinator, first)
    assert_receive {:test_agent_runtime_stream, first_provider, _}
    reply(first_provider, :speaker, "first")
    assert_receive {:vxpipe_capability_text, _, ^first, "first"}
    assert_receive {:vxpipe_capability_text_complete, _, ^first}

    assert {:accepted, :non_blocking} =
             submit_invocation(runtime, :non_blocking, "interrupt-overlap")

    assert_receive {:submitted_host_tool_started, execution, "interrupt-overlap"}
    send(execution, :release_submitted_host_tool)

    assert_receive {:test_agent_runtime_stream, overlap_provider, _}, 500
    overlap_monitor = Process.monitor(overlap_provider)

    assert {:ok, _} = Coordinator.interrupt(runtime.coordinator, [])
    assert_receive {:DOWN, ^overlap_monitor, :process, ^overlap_provider, _reason}

    # Held output must never reach the room after cancel.
    refute_received {:vxpipe_capability_text, _, _, "first"}
    assert :ok = Coordinator.settle_output(runtime.coordinator, first, "first")
    refute_received {:vxpipe_capability_text, _, _, _}
  end

  for playback <- [:visible, :untracked] do
    @playback playback
    test "caller onset with #{playback} playback keeps an earlier tool result in the next transcript request" do
      runtime = start_runtime(history_mode: :host_settled, completion_target: self())
      prior = command("previous", "Please save my location.")
      correction = command("correction", "Actually Georgia")

      if @playback == :visible do
        assert :ok = Coordinator.respond(runtime.coordinator, prior)
        assert_receive {:test_agent_runtime_stream, provider, _}
        reply(provider, :speaker, "I'll check.")
        assert_receive {:vxpipe_capability_text, _, ^prior, "I'll check."}
        assert_receive {:vxpipe_capability_text_complete, _, ^prior}
      end

      assert {:accepted, :non_blocking} =
               submit_invocation(runtime, :non_blocking, "area-written")

      assert_receive {:submitted_host_tool_started, execution, "area-written"}

      if @playback == :visible do
        prior_id = Vxpipe.CallEngine.RoomAuthority.TurnState.key(prior)

        assert {:ok, _} =
                 Coordinator.interrupt(
                   runtime.coordinator,
                   [prior_id],
                   correction.participant_id,
                   correction.connection_id
                 )

        assert :ok = Coordinator.settle_output(runtime.coordinator, prior, "I'll check.")
      else
        assert :ok =
                 Coordinator.interrupt_untracked(
                   runtime.coordinator,
                   correction.participant_id,
                   correction.connection_id
                 )
      end

      send(execution, :release_submitted_host_tool)
      assert_receive {:vxpipe_tool_completion_available, _, "area-written"}
      assert :ok = Coordinator.respond(runtime.coordinator, correction)
      assert_receive {:test_agent_runtime_stream, provider, request}
      assert List.last(request.messages).content =~ "Actually Georgia"

      assert Enum.count(
               request.messages,
               &(&1.origin == :engine and &1.content =~ "area-written")
             ) == 1

      reply(provider, :speaker, "Thanks for correcting that.")
    end
  end

  test "a tool finishing after source retirement is retained privately on connection reuse" do
    runtime = start_runtime(history_mode: :host_settled, completion_target: self())
    first = command("departing", "Retire me")
    assert {:accepted, :non_blocking} = submit_invocation(runtime, :non_blocking, "late-fact")
    assert_receive {:submitted_host_tool_started, execution, "late-fact"}

    assert :ok =
             Coordinator.retire_source(
               runtime.coordinator,
               first.participant_id,
               first.connection_id
             )

    send(execution, :release_submitted_host_tool)

    # Once the tool is terminal, the next caller's request must be first.
    assert_receive {:vxpipe_tool_completion_available, _registry, "late-fact"}
    next = command("reconnected", "Hello again")
    assert :ok = Coordinator.respond(runtime.coordinator, next)
    assert_receive {:test_agent_runtime_stream, provider, request}
    assert List.last(request.messages).content =~ "Hello again"
    assert Enum.any?(request.messages, &(&1.origin == :engine and &1.content =~ "late-fact"))
    reply(provider, :speaker, "Welcome back.")
  end

  for scope <- [:connection, :participant] do
    test "retiring the #{scope} discards an already generated reply behind active playback" do
      runtime = start_runtime(history_mode: :host_settled)
      first = command("playing", "Florida")
      assert :ok = Coordinator.respond(runtime.coordinator, first)
      assert_receive {:test_agent_runtime_stream, provider, _}
      reply(provider, :speaker, "Let me save that.")
      assert_receive {:vxpipe_capability_text_complete, _, ^first}
      assert {:accepted, :non_blocking} = submit_invocation(runtime, :non_blocking, "held-save")
      assert_receive {:submitted_host_tool_started, executing, "held-save"}
      send(executing, :release_submitted_host_tool)
      assert_receive {:test_agent_runtime_stream, second, _}
      worker = :sys.get_state(runtime.coordinator).current.task.pid
      monitor = Process.monitor(worker)
      reply(second, :speaker, "Saved Florida.")
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
      _ = :sys.get_state(runtime.coordinator)
      connection = if unquote(scope) == :connection, do: first.connection_id

      assert :ok =
               Coordinator.retire_source(runtime.coordinator, first.participant_id, connection, [
                 first.id
               ])

      assert :ok = Coordinator.settle_output(runtime.coordinator, first, "Let me")
      next = command("later", "What did you hear?")
      assert :ok = Coordinator.respond(runtime.coordinator, next)
      assert_receive {:test_agent_runtime_stream, provider, request}
      assert Enum.any?(request.messages, &(&1.origin == :engine and &1.content =~ "held-save"))
      assert Enum.any?(request.messages, &(&1.role == :assistant and &1.content =~ "Let me"))
      refute Enum.any?(request.messages, &(&1.content =~ "Saved Florida."))
      refute_received {:vxpipe_capability_text, _, _, "Saved Florida."}
      reply(provider, :speaker, "Let me.")
    end
  end

  test "out-of-order tool completions keep their own results and speech order" do
    runtime = start_runtime(history_mode: :host_settled)
    first = command("playing", "Check both")
    assert :ok = Coordinator.respond(runtime.coordinator, first)
    assert_receive {:test_agent_runtime_stream, provider, _}
    reply(provider, :speaker, "Checking.")
    assert_receive {:vxpipe_capability_text_complete, _, ^first}

    assert {:accepted, :non_blocking} = submit_invocation(runtime, :non_blocking, "slow")
    assert_receive {:submitted_host_tool_started, slow, "slow"}
    assert {:accepted, :non_blocking} = submit_invocation(runtime, :non_blocking, "fast")
    assert_receive {:submitted_host_tool_started, fast, "fast"}
    send(fast, :release_submitted_host_tool)
    assert_receive {:test_agent_runtime_stream, fast_reply, request}
    assert List.last(request.messages).content =~ "fast"
    send(slow, :release_submitted_host_tool)
    worker = :sys.get_state(runtime.coordinator).current.task.pid
    monitor = Process.monitor(worker)
    reply(fast_reply, :speaker, "Fast result.")
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    _ = :sys.get_state(runtime.coordinator)
    refute_received {:test_agent_runtime_stream, _, _}
    refute_received {:vxpipe_capability_text, _, _, "Fast result."}

    assert :ok = Coordinator.settle_output(runtime.coordinator, first, "Checking.")
    assert_receive {:vxpipe_capability_text, _, fast_command, "Fast result."}
    assert_receive {:test_agent_runtime_stream, slow_reply, request}
    assert List.last(request.messages).content =~ "slow"
    reply(slow_reply, :speaker, "Slow result.")
    assert :ok = Coordinator.settle_output(runtime.coordinator, fast_command, "Fast result.")
    assert_receive {:vxpipe_capability_text, _, _, "Slow result."}
  end

  defp start_runtime(options) do
    suffix = System.unique_integer([:positive])
    activation_id = "act-overlap-#{suffix}"
    session_name = {:global, {:test_overlap_session, suffix}}
    request_supervisor_name = {:global, {:test_overlap_request_sup, suffix}}
    registry_name = {:global, {:test_overlap_registry, suffix}}

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
         maximum_pending_requests: Keyword.get(options, :maximum_pending_requests, 2),
         reply_protocol: :mode_message_v1,
         history_mode: Keyword.get(options, :history_mode, :generated)}
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
         reply_protocol: :mode_message_v1,
         history_mode: Keyword.get(options, :history_mode, :generated),
         model_provider: TestAgentRuntimeModelProvider,
         model: %{owner: self()},
         tools: Keyword.get(options, :tools, []),
         executor: Keyword.get(options, :executor),
         pending_context_source:
           {Vxpipe.CallEngine.AgentRuntime.PendingContextSource, registry_name},
         model_context_source:
           {ModelContextSource,
            %ModelContextSource{
              variable_binding: nil,
              transfer_reason: nil,
              coordinator: coordinator
            }},
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
