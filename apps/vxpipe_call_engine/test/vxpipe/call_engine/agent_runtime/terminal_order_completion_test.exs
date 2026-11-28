defmodule Vxpipe.CallEngine.AgentRuntime.TerminalOrderCompletionTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{ModelResponse, Session, ToolCall, ToolDescriptor}
  alias Vxpipe.CallEngine.AgentRuntime.{Coordinator, InvocationExecutor, PendingContextSource}
  alias Vxpipe.CallEngine.CallSpec.Guardrails
  alias Vxpipe.CallEngine.Guardrails.{Participant, RuntimeAdmission}
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedHostTool

  alias Vxpipe.CallEngine.Tool.{
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

  alias Vxpipe.CallEngine.Usage.ProviderContext

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
    end)
  end

  for mode <- [:blocking, :non_blocking] do
    test "a silent terminal call waits for the #{mode} worker with no guardrail policy" do
      runtime =
        start_runtime(
          tools: [ordinary_descriptor(unquote(mode)), terminal_descriptor(:blocking)],
          executor: InvocationExecutor
        )

      input = command("terminal-finish", "Move please")
      :ok = Coordinator.respond(runtime.coordinator, input)
      assert_receive {:test_agent_runtime_stream, provider, _}, 1_000

      {:ok, response} =
        ModelResponse.new(
          text: "",
          tool_calls: [
            tool_call("term-1", "terminal_tool", %{"value" => "terminal"}),
            tool_call("ord-1", "ordinary_tool", %{"value" => "ordinary"})
          ]
        )

      send(provider, {:test_agent_runtime_response, {:ok, response}})
      assert_receive {:submitted_host_tool_started, ordinary, "ordinary"}, 1_000
      assert {:ok, :running} = InvocationRegistry.peek_completion(runtime.registry, "ord-1")
      assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "term-1")
      refute_received {:submitted_host_tool_started, _, "terminal"}
      send(ordinary, :release_submitted_host_tool)
      assert_receive {:submitted_host_tool_started, terminal, "terminal"}, 2_000

      assert InvocationRegistry.peek_completion(runtime.registry, "ord-1") in [
               {:ok, {:ok, %{"value" => "ordinary"}}},
               {:ok, :consumed}
             ]

      send(terminal, :release_submitted_host_tool)
    end
  end

  test "ordinary failure withholds terminal for a later distinct proposal" do
    runtime =
      start_runtime(
        tools: [ordinary_descriptor(:blocking), terminal_descriptor(:blocking)],
        executor: InvocationExecutor
      )

    command = command("terminal-withhold", "Move please")
    assert :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _request}, 1_000

    {:ok, response} =
      ModelResponse.new(
        text: "",
        tool_calls: [
          tool_call("term-2", "terminal_tool", %{"value" => "terminal"}),
          tool_call("ord-2", "ordinary_tool", %{"unexpected" => "args"})
        ]
      )

    send(provider, {:test_agent_runtime_response, {:ok, response}})

    # Reaching the next provider round acknowledges submission and completion processing.
    assert_receive {:test_agent_runtime_stream, _provider, next}, 2_000

    assert Enum.any?(next.messages, fn message ->
             message.role == :tool and message.content =~ "ordinary_failed"
           end)

    assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "term-2")
    refute_received {:submitted_host_tool_started, _, "terminal"}
  end

  for {after_verdict, transfer_verdict} <- [
        {:pass, :pass},
        {:pass, :block},
        {:block, :pass},
        {:block, :block},
        {:error, :pass}
      ],
      first <- [:after_turn, :before_outgoing_transfer] do
    test "mixed proposal holds for both checks: #{after_verdict}/#{transfer_verdict}, #{first} finishes first" do
      runtime = guarded_runtime()
      command = command("joint", "Please transfer me.")
      workers = start_mixed(runtime, command)

      verdicts = %{
        after_turn: unquote(after_verdict),
        before_outgoing_transfer: unquote(transfer_verdict)
      }

      [first, second] = Enum.sort_by(Map.keys(workers), &(&1 != unquote(first)))
      resolve(workers[first], verdicts[first])
      assert_withheld(runtime, command)
      resolve(workers[second], verdicts[second])

      case {unquote(after_verdict), unquote(transfer_verdict)} do
        {:pass, :pass} ->
          assert_receive {:"$gen_call", from, {:bind_transfer_verdict, %{invocation_id: "term"}}}
          GenServer.reply(from, :ok)
          assert_receive {:submitted_host_tool_started, ordinary, "ordinary"}
          assert {:ok, :running} = InvocationRegistry.peek_completion(runtime.registry, "ord")
          assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "term")
          send(ordinary, :release_submitted_host_tool)
          assert_receive {:submitted_host_tool_started, terminal, "terminal"}
          send(terminal, :release_submitted_host_tool)
          refute_received {:submitted_host_tool_started, _, "terminal"}

        {:error, _} ->
          assert_receive {:vxpipe_capability_failed, _, ^command, _}
          assert_withheld(runtime, command)
          refute_received {:test_agent_runtime_stream, _, _}

        _ ->
          assert_receive {:test_agent_runtime_stream, repair, request}
          assert request.tools == []
          private = List.last(request.messages).content |> JSON.decode!()
          assert private["type"] == "guardrail_failure"

          assert Enum.map(private["failures"], & &1["event"]) ==
                   for(
                     event <- [:after_turn, :before_outgoing_transfer],
                     verdicts[event] == :block,
                     do: Atom.to_string(event)
                   )

          assert_withheld(runtime, command)
          send_response(repair, "A permitted replacement.", [])
          assert_receive {:guardrail_check, :after_turn, worker}
          assert_withheld(runtime, command)
          resolve(worker, :pass)
          assert_receive {:vxpipe_capability_text, _, ^command, "A permitted replacement."}
          assert_receive {:vxpipe_capability_text_complete, _, ^command}
          assert :ok = Coordinator.respond(runtime.coordinator, command("later", "Next question"))
          assert_receive {:test_agent_runtime_stream, _, later}
          history = Enum.map_join(later.messages, "\n", &(&1.content || ""))
          assert history =~ "A permitted replacement."
          refute history =~ "Private draft."
          refute history =~ "guardrail_failure"
          refute Enum.any?(later.messages, &(&1.role == :tool))
          refute_received {:submitted_host_tool_started, _, _}
      end
    end
  end

  test "interruption cancels held checks without submitting the mixed round" do
    runtime = guarded_runtime()
    command = command("interrupt", "Please transfer me.")
    workers = start_mixed(runtime, command)
    monitors = Enum.map(workers, fn {_, worker} -> Process.monitor(worker) end)
    assert {:ok, _} = Coordinator.interrupt(runtime.coordinator, [])
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _})
    assert_withheld(runtime, command)
    assert :ok = Coordinator.respond(runtime.coordinator, command("later", "Fresh question"))
    assert_receive {:test_agent_runtime_stream, _, later}
    refute Enum.any?(later.messages, &(&1.role == :tool))
  end

  test "a silent transfer checks only the handoff and waits for the ordinary worker" do
    runtime = guarded_runtime()
    input = command("silent-transfer", "Connect me.")
    :ok = Coordinator.respond(runtime.coordinator, input)
    assert_receive {:test_agent_runtime_stream, provider, _}

    {:ok, candidate} =
      ModelResponse.new(
        text: "",
        tool_calls: [
          tool_call("term", "terminal_tool", %{"value" => "terminal", "destination" => "billing"}),
          tool_call("ord", "ordinary_tool", %{"value" => "ordinary"})
        ]
      )

    send(provider, {:test_agent_runtime_response, {:ok, candidate}})
    assert_receive {:guardrail_check, :before_outgoing_transfer, checker}
    assert_withheld(runtime, input)
    resolve(checker, :pass)
    assert_receive {:"$gen_call", from, {:bind_transfer_verdict, %{invocation_id: "term"}}}
    GenServer.reply(from, :ok)
    assert_receive {:submitted_host_tool_started, ordinary_worker, "ordinary"}
    assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "term")
    send(ordinary_worker, :release_submitted_host_tool)
    assert_receive {:submitted_host_tool_started, terminal_worker, "terminal"}
    refute_received {:guardrail_check, :after_turn, _}
    refute_received {:vxpipe_capability_text, _, ^input, _}
    send(terminal_worker, :release_submitted_host_tool)
  end

  test "an admitted silent tool remains committed exactly once when a later spoken round needs repair" do
    runtime = guarded_runtime()
    input = command("keep-tool", "Look it up.")
    :ok = Coordinator.respond(runtime.coordinator, input)
    assert_receive {:test_agent_runtime_stream, provider, _}

    {:ok, silent} =
      ModelResponse.new(
        text: "",
        tool_calls: [
          tool_call("first-lookup", "ordinary_tool", %{"value" => "kept"})
        ]
      )

    send(provider, {:test_agent_runtime_response, {:ok, silent}})
    assert_receive {:submitted_host_tool_started, ordinary_worker, "kept"}
    assert_receive {:test_agent_runtime_stream, next_provider, _}
    refute_received {:guardrail_check, _, _}
    send_response(next_provider, "Rejected follow-up.", [])
    assert_receive {:guardrail_check, :after_turn, checker}
    resolve(checker, :block)
    assert_receive {:test_agent_runtime_stream, repair, retry_request}
    assert retry_request.tools == []
    assert Enum.count(retry_request.messages, &(&1.role == :tool)) == 1
    send_response(repair, "I found it.", [])
    assert_receive {:guardrail_check, :after_turn, checker}
    refute_received {:vxpipe_capability_text, _, ^input, _}
    resolve(checker, :pass)
    assert_receive {:vxpipe_capability_text, _, ^input, "I found it."}
    assert_receive {:vxpipe_capability_text_complete, _, ^input}
    refute_received {:submitted_host_tool_started, _, _}
    send(ordinary_worker, :release_submitted_host_tool)
  end

  test "interrupting a repair cancels the checker and keeps its draft and feedback out of the next request" do
    runtime = guarded_runtime()
    input = command("cancel-repair", "Move me.")
    workers = start_mixed(runtime, input)
    resolve(workers.after_turn, :block)
    resolve(workers.before_outgoing_transfer, :pass)
    assert_receive {:test_agent_runtime_stream, repair, _}
    send_response(repair, "Replacement in progress.", [])
    assert_receive {:guardrail_check, :after_turn, checker}
    monitor = Process.monitor(checker)
    assert {:ok, _} = Coordinator.interrupt(runtime.coordinator, [])
    assert_receive {:DOWN, ^monitor, :process, ^checker, _}
    assert_withheld(runtime, input)
    :ok = Coordinator.respond(runtime.coordinator, command("fresh", "A fresh question."))
    assert_receive {:test_agent_runtime_stream, _, next}
    history = Enum.map_join(next.messages, "\n", &(&1.content || ""))
    refute history =~ "Private draft."
    refute history =~ "Replacement in progress."
    refute history =~ "guardrail_failure"
  end

  defp guarded_runtime do
    start_runtime(
      tools: [ordinary_descriptor(:non_blocking), terminal_descriptor(:blocking)],
      executor: InvocationExecutor,
      guarded: true
    )
  end

  defp start_mixed(runtime, command) do
    :ok = Coordinator.respond(runtime.coordinator, command)
    assert_receive {:test_agent_runtime_stream, provider, _}

    send_response(provider, "Private draft.", [
      tool_call("term", "terminal_tool", %{"value" => "terminal", "destination" => "billing"}),
      tool_call("ord", "ordinary_tool", %{"value" => "ordinary"})
    ])

    assert_receive {:guardrail_check, :after_turn, speech}
    assert_receive {:guardrail_check, :before_outgoing_transfer, transfer}
    assert_withheld(runtime, command)
    %{after_turn: speech, before_outgoing_transfer: transfer}
  end

  defp send_response(provider, text, calls) do
    send(provider, {:test_agent_runtime_delta, text, self()})
    assert_receive {:test_agent_runtime_delta_result, :ok}
    {:ok, response} = ModelResponse.new(text: text, tool_calls: calls)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_withheld(runtime, command) do
    _ = :sys.get_state(runtime.coordinator)
    refute_received {:vxpipe_capability_text, _, ^command, _}
    refute_received {:submitted_host_tool_started, _, _}
    assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "ord")
    assert {:error, :unknown} = InvocationRegistry.peek_completion(runtime.registry, "term")
  end

  defp resolve(worker, verdict) do
    monitor = Process.monitor(worker)
    send(worker, {:answer, verdict})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
  end

  defp admission(task_supervisor, activation_id) do
    owner = self()
    question = %{"id" => "allowed", "question" => "Is it allowed?", "required_answer" => "yes"}

    {:ok, policy} =
      Guardrails.new(
        %{
          "after_turn" => [question],
          "before_outgoing_transfer" => [%{question | "id" => "route"}]
        },
        []
      )

    adapter = fn request ->
      send(owner, {:guardrail_check, request.event, self()})
      [question] = request.questions

      receive do
        {:answer, :pass} -> {:ok, %{scores: %{question.id => 1.0}}}
        {:answer, :block} -> {:ok, %{scores: %{question.id => 0.0}}}
        {:answer, :error} -> {:error, :unavailable}
      end
    end

    service =
      start_supervised!(
        {Participant, policy: policy, request_supervisor: task_supervisor, adapter: adapter}
      )

    {RuntimeAdmission,
     %{
       guardrails: service,
       room_authority: owner,
       activation_id: activation_id,
       after_questions: policy.after_turn,
       transfer_questions: policy.before_outgoing_transfer,
       terminal_kinds: %{"terminal_tool" => :transfer, "ordinary_tool" => :ordinary}
     }}
  end

  defp ordinary_descriptor(conversation_mode) do
    build_descriptor("ordinary_tool", conversation_mode, false)
  end

  defp terminal_descriptor(conversation_mode) do
    build_descriptor("terminal_tool", conversation_mode, true)
  end

  defp build_descriptor(name, conversation_mode, terminal?) do
    resolved = %ToolBinding{
      name: "submitted_host_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedHostTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)
    binding = %{binding | name: name, conversation_mode: conversation_mode}

    assert {:ok, descriptor} =
             ToolDescriptor.new(
               name: name,
               description: "Controlled test tool",
               input_schema: %{
                 "type" => "object",
                 "properties" => %{"value" => %{"type" => "string"}},
                 "additionalProperties" => true
               },
               binding: binding,
               terminal?: terminal?
             )

    descriptor
  end

  defp tool_call(id, name, arguments) do
    {:ok, call} = ToolCall.new(id: id, name: name, arguments: arguments)
    call
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

  defp start_runtime(options) do
    suffix = System.unique_integer([:positive])
    activation_id = "act-terminal-order-#{suffix}"
    session_name = {:global, {:test_terminal_order_session, suffix}}
    request_supervisor_name = {:global, {:test_terminal_order_requests, suffix}}
    registry_name = {:global, {:test_terminal_order_registry, suffix}}

    request_supervisor =
      start_supervised!({Task.Supervisor, name: request_supervisor_name})

    coordinator =
      start_supervised!(
        {Coordinator,
         [
           activation_id: activation_id,
           agent_participant_id: "participant-agent",
           call_id: "call-demo",
           session: session_name,
           invocation_registry: registry_name,
           request_supervisor: request_supervisor_name,
           owner: self(),
           provider: :local_fixture,
           usage_provider: usage_provider_context(),
           maximum_output_bytes: 4_096,
           maximum_pending_requests: 2,
           history_mode: :generated
         ]}
      )

    invocation_supervisor =
      start_supervised!({InvocationSupervisor, activation_id: activation_id, maximum_children: 4})

    _registry =
      start_supervised!(
        {InvocationRegistry,
         activation_id: activation_id,
         name: registry_name,
         invocation_supervisor: invocation_supervisor,
         completion_target: coordinator,
         maximum_invocations: 4,
         maximum_consumed_invocations: 8,
         invocation_timeout_ms: 1_000,
         maximum_result_bytes: 4_096}
      )

    round_admission = if options[:guarded], do: admission(request_supervisor, activation_id)

    _session =
      start_supervised!(
        {Session,
         name: session_name,
         instructions: "Answer briefly.",
         history_mode: :generated,
         round_admission: round_admission,
         model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
         model: %{owner: self()},
         tools: Keyword.fetch!(options, :tools),
         executor: Keyword.fetch!(options, :executor),
         pending_context_source: {PendingContextSource, registry_name},
         event_destination: coordinator,
         maximum_output_bytes: 4_096,
         request_timeout_ms: 5_000}
      )

    %{coordinator: coordinator, registry: registry_name}
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
end
