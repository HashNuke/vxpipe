defmodule Vxpipe.CallEngine.AgentCoordinatorTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

  alias Jido.AI.Runtime.Event
  alias Vxpipe.CallEngine.Agent
  alias Vxpipe.CallEngine.AgentCoordinator
  alias Vxpipe.CallEngine.AgentFactory
  alias Vxpipe.CallEngine.JidoAgentRuntime
  alias Vxpipe.CallEngine.Command.{ContinueAgent, SendText}
  alias Vxpipe.CallEngine.TestBlockingTool
  alias Vxpipe.CallEngine.TestAgentTool
  alias Vxpipe.CallEngine.TestAgentRuntime
  alias Vxpipe.CallEngine.Tool.Call
  alias Vxpipe.CallEngine.Tool.{BackgroundSupervisor, Dispatcher}

  @model_first_token_event [:vxpipe, :call_engine, :model, :first_token]
  @model_request_stop_event [:vxpipe, :call_engine, :model, :request, :stop]
  @provider_failure_event [:vxpipe, :call_engine, :provider, :failure]

  test "reports first model output once and a payload-free successful outcome" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    coordinator = start_coordinator(provider: :req_llm)
    sentinel = "private-model-output"
    command = command("observed-model-timing", "private-model-input")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _options}

    emit(coordinator, request_id, :llm_delta, %{chunk_type: :content, delta: sentinel})

    assert_receive {:telemetry_event, @model_first_token_event, %{duration: duration},
                    %{provider: :req_llm} = first_metadata}

    assert is_integer(duration)
    assert duration >= 0
    assert first_metadata == %{provider: :req_llm}
    refute inspect(first_metadata) =~ sentinel

    emit(coordinator, request_id, :llm_delta, %{chunk_type: :content, delta: " finished."})
    emit(coordinator, request_id, :request_completed, %{result: sentinel <> " finished."})

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: total_duration},
                    stop_metadata}

    assert is_integer(total_duration)
    assert total_duration >= duration
    assert stop_metadata == %{provider: :req_llm, outcome: :ok, first_output: :observed}
    refute_receive {:telemetry_event, @model_first_token_event, _, _}
    refute_receive {:telemetry_event, @provider_failure_event, _, _}
  end

  test "keeps first output missing and reports a safe provider failure" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    coordinator = start_coordinator(provider: :req_llm)
    command = command("missing-model-output", "private-model-input")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _options}

    emit(coordinator, request_id, :request_failed, %{error: "private-provider-error"})

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: duration},
                    stop_metadata}

    assert is_integer(duration)
    assert duration >= 0
    assert stop_metadata == %{provider: :req_llm, outcome: :unavailable, first_output: :missing}

    assert_receive {:telemetry_event, @provider_failure_event, %{count: 1}, failure_metadata}

    assert failure_metadata == %{
             capability: :model,
             provider: :req_llm,
             category: :unavailable
           }

    refute_receive {:telemetry_event, @model_first_token_event, _, _}
  end

  test "reports a runtime cancellation as incomplete without a provider failure" do
    attach_telemetry_events([
      @model_first_token_event,
      @model_request_stop_event,
      @provider_failure_event
    ])

    coordinator = start_coordinator(provider: :req_llm)
    command = command("cancelled-model-request", "private-model-input")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _options}

    emit(coordinator, request_id, :request_cancelled, %{})

    assert_receive {:vxpipe_capability_failed, ^coordinator, ^command, :interrupted}

    assert_receive {:telemetry_event, @model_request_stop_event, %{duration: duration},
                    %{provider: :req_llm, outcome: :cancelled, first_output: :missing}}

    assert is_integer(duration)
    assert duration >= 0
    refute_receive {:telemetry_event, @model_first_token_event, _, _}
    refute_receive {:telemetry_event, @provider_failure_event, _, _}
  end

  test "attributes controlled diagnostic outcomes to the local fixture" do
    attach_telemetry_events([@model_request_stop_event, @provider_failure_event])

    coordinator = start_coordinator(provider: :local_fixture)
    command = command("local-fixture-failure", "private-model-input")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _options}
    emit(coordinator, request_id, :request_failed, %{})

    assert_receive {:telemetry_event, @model_request_stop_event, _measurements,
                    %{provider: :local_fixture, outcome: :unavailable, first_output: :missing}}

    assert_receive {:telemetry_event, @provider_failure_event, %{count: 1},
                    %{provider: :local_fixture, category: :unavailable}}
  end

  test "projects streamed sentences and one tool lifecycle onto the existing contract" do
    coordinator = start_coordinator(request_options: [model: "google:configured-model"])
    command = command("stream-tool", "check a value")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, "check a value", options}
    assert Keyword.fetch!(options, :stream_to) == {:pid, coordinator}

    assert Keyword.fetch!(options, :request_transformer) ==
             Vxpipe.CallEngine.AgentRequestTransformer

    assert options
           |> Keyword.fetch!(:tool_context)
           |> Map.fetch!(:vxpipe_model) == "google:configured-model"

    assert Keyword.fetch!(options, :extra_refs) == %{
             vxpipe_command_id: command.id,
             vxpipe_request_id: request_id
           }

    emit(
      coordinator,
      request_id,
      :llm_delta,
      %{chunk_type: :content, delta: "First sentence. Sec"},
      llm_call_id: "llm-one"
    )

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command, "First sentence."}
    refute_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}

    emit(
      coordinator,
      request_id,
      :tool_started,
      %{
        tool_call_id: "tool-one",
        tool_name: "test_agent_tool",
        arguments: %{"value" => "one"}
      },
      tool_call_id: "tool-one",
      tool_name: "test_agent_tool"
    )

    assert_receive {:vxpipe_capability_tool_started, ^coordinator, ^command,
                    %Call{
                      id: "tool-one",
                      name: "test_agent_tool",
                      arguments: %{"value" => "one"}
                    } = call}

    emit(
      coordinator,
      request_id,
      :tool_completed,
      %{
        tool_call_id: "tool-one",
        tool_name: "test_agent_tool",
        result: {:ok, %{"value" => "one"}, []}
      },
      tool_call_id: "tool-one",
      tool_name: "test_agent_tool"
    )

    assert_receive {:vxpipe_capability_tool_completed, ^coordinator, ^command, ^call,
                    %{"value" => "one"}}

    emit(coordinator, request_id, :llm_delta, %{chunk_type: :content, delta: "ond sentence!"},
      llm_call_id: "llm-two"
    )

    emit(coordinator, request_id, :request_completed, %{
      result: "First sentence. Second sentence.",
      usage: %{}
    })

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command, "Second sentence!"}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
    refute_receive {:vxpipe_capability_text, ^coordinator, ^command, _duplicate}
  end

  test "preserves buffered mixed tool text and does not redeliver streamed text" do
    coordinator = start_coordinator()
    command = command("mixed-tool-text", "start it")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _options}

    emit(
      coordinator,
      request_id,
      :llm_completed,
      %{turn_type: :tool_calls, text: "I started the report."},
      llm_call_id: "llm-buffered"
    )

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command, "I started the report."}

    emit(
      coordinator,
      request_id,
      :llm_delta,
      %{chunk_type: :content, delta: "It is still running."},
      llm_call_id: "llm-streamed"
    )

    emit(
      coordinator,
      request_id,
      :llm_completed,
      %{turn_type: :answer, text: "It is still running."},
      llm_call_id: "llm-streamed"
    )

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command, "It is still running."}

    emit(coordinator, request_id, :request_completed, %{result: "It is still running."})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}
    refute_receive {:vxpipe_capability_text, ^coordinator, ^command, _duplicate}
  end

  test "reports a provider failure and remains available for the next request" do
    coordinator = start_coordinator()
    failed = command("failed", "first")
    replacement = command("replacement-after-failure", "second")

    assert :ok = AgentCoordinator.respond(coordinator, failed)
    assert_receive {:test_agent_request, ^coordinator, failed_request_id, "first", _options}

    emit(coordinator, failed_request_id, :request_failed, %{error: :provider_failure})

    assert_receive {:vxpipe_capability_failed, ^coordinator, ^failed, :provider_unavailable}
    _ = :sys.get_state(coordinator)

    assert :ok = AgentCoordinator.respond(coordinator, replacement)

    assert_receive {:test_agent_request, ^coordinator, _replacement_request_id, "second",
                    _options}
  end

  test "times out one request, ignores its stale terminal event, and advances the bounded queue" do
    coordinator = start_coordinator(request_timeout_ms: 250, maximum_pending_requests: 1)
    timed_out = command("timed-out", "take too long")
    queued = command("queued", "continue")
    rejected = command("rejected", "too many")

    assert :ok = AgentCoordinator.respond(coordinator, timed_out)
    assert_receive {:test_agent_request, ^coordinator, timed_out_request, _, _}
    assert :ok = AgentCoordinator.respond(coordinator, queued)
    assert {:error, :queue_full} = AgentCoordinator.respond(coordinator, rejected)

    assert_receive {:test_agent_cancel, ^coordinator, ^timed_out_request, :provider_timeout},
                   500

    assert_receive {:vxpipe_capability_failed, ^coordinator, ^timed_out, :provider_timeout},
                   500

    assert_receive {:test_agent_request, ^coordinator, queued_request, "continue", _}, 500

    emit(coordinator, timed_out_request, :request_completed, %{result: "stale"})
    refute_receive {:vxpipe_capability_text, ^coordinator, ^timed_out, "stale"}

    emit(coordinator, queued_request, :request_completed, %{result: "continued"})
    assert_receive {:vxpipe_capability_text, ^coordinator, ^queued, "continued"}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}
  end

  test "an oversized terminal response fails only its request before advancing the queue" do
    coordinator = start_coordinator(maximum_output_bytes: 4)
    oversized = command("oversized", "first")
    queued = command("after-oversized", "second")

    assert :ok = AgentCoordinator.respond(coordinator, oversized)
    assert_receive {:test_agent_request, ^coordinator, oversized_request, _, _}
    assert :ok = AgentCoordinator.respond(coordinator, queued)

    emit(coordinator, oversized_request, :request_completed, %{result: "too large"})

    assert_receive {:test_agent_cancel, ^coordinator, ^oversized_request, :invalid_response}
    assert_receive {:vxpipe_capability_failed, ^coordinator, ^oversized, :invalid_response}
    refute_receive {:vxpipe_capability_text_complete, ^coordinator, ^oversized}

    assert_receive {:test_agent_request, ^coordinator, queued_request, "second", _}
    refute_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}

    emit(coordinator, queued_request, :request_completed, %{result: "done"})
    assert_receive {:vxpipe_capability_text, ^coordinator, ^queued, "done"}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^queued}
  end

  test "reorders runtime events before projecting a tool lifecycle" do
    coordinator = start_coordinator()
    command = command("out-of-order", "check order")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, _, _}

    emit(
      coordinator,
      request_id,
      :tool_completed,
      %{
        tool_call_id: "tool-ordered",
        tool_name: "test_agent_tool",
        result: {:ok, %{"value" => "ordered"}, []}
      },
      seq: 2,
      tool_call_id: "tool-ordered",
      tool_name: "test_agent_tool"
    )

    refute_receive {:vxpipe_capability_tool_completed, ^coordinator, ^command, _, _}
    refute_receive {:vxpipe_capability_failed, ^coordinator, ^command, _reason}

    emit(
      coordinator,
      request_id,
      :tool_started,
      %{
        tool_call_id: "tool-ordered",
        tool_name: "test_agent_tool",
        arguments: %{"value" => "ordered"}
      },
      seq: 1,
      tool_call_id: "tool-ordered",
      tool_name: "test_agent_tool"
    )

    assert_receive {:vxpipe_capability_tool_started, ^coordinator, ^command,
                    %Call{id: "tool-ordered"} = call}

    assert_receive {:vxpipe_capability_tool_completed, ^coordinator, ^command, ^call,
                    %{"value" => "ordered"}}
  end

  test "cancels current and queued turns, discards selected completed context, then accepts replacement work" do
    coordinator = start_coordinator()
    completed = command("completed", "old topic")

    assert :ok = AgentCoordinator.respond(coordinator, completed)
    assert_receive {:test_agent_request, ^coordinator, completed_request, _, _}
    emit(coordinator, completed_request, :request_completed, %{result: "old answer"})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^completed}

    current = command("current", "keep talking")
    queued = command("queued", "wait")

    assert :ok = AgentCoordinator.respond(coordinator, current)
    assert_receive {:test_agent_request, ^coordinator, current_request, _, _}
    assert :ok = AgentCoordinator.respond(coordinator, queued)

    completed_identity = {completed.connection_id, completed.correlation_id, completed.id}

    assert {:ok, [^current, ^queued]} =
             AgentCoordinator.interrupt(coordinator, [completed_identity])

    assert_receive {:test_agent_cancel, ^coordinator, ^current_request, :interrupted}
    assert_receive {:test_agent_discard, ^coordinator, [^completed_request]}

    emit(coordinator, current_request, :request_completed, %{result: "stale answer"})
    refute_receive {:vxpipe_capability_text, ^coordinator, ^current, "stale answer"}

    replacement = command("replacement", "new topic")
    assert :ok = AgentCoordinator.respond(coordinator, replacement)

    assert_receive {:test_agent_request, ^coordinator, replacement_request, "new topic",
                    replacement_options}

    assert replacement_options
           |> Keyword.fetch!(:tool_context)
           |> Map.fetch!(:vxpipe_discarded_agent_request_ids) == [completed_request]

    emit(coordinator, replacement_request, :request_completed, %{result: "new answer"})

    assert_receive {:vxpipe_capability_text, ^coordinator, ^replacement, "new answer"}
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}
  end

  test "maps one real Jido action round without owning a replacement inference loop" do
    activation_id = "act-real-#{System.unique_integer([:positive])}"

    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: activation_id, tools: [TestAgentTool], maximum_result_bytes: 4_096}
      )

    agent_server =
      start_supervised!(
        {Jido.AgentServer,
         agent: Agent, id: activation_id, jido: Vxpipe.CallEngine.Jido, register_global: false}
      )

    assert :ok =
             AgentFactory.configure(
               agent_server,
               system_prompt: "Use the configured host action.",
               tools: [TestAgentTool]
             )

    script =
      expect_react do
        user("check it")
        call("test_agent_tool", %{"value" => "checked"}, id: "tool-real")
        answer("The host action completed.")
      end

    coordinator =
      start_supervised!(
        {AgentCoordinator,
         activation_id: activation_id,
         agent_participant_id: "agent-real",
         agent_server: agent_server,
         agent_runtime: JidoAgentRuntime,
         owner: self(),
         tool_dispatcher: dispatcher,
         maximum_output_bytes: 65_536,
         maximum_pending_requests: 2,
         request_options: Jido.AI.Test.react_opts(script),
         request_timeout_ms: 2_000}
      )

    command = command("real-jido", "check it")
    assert :ok = AgentCoordinator.respond(coordinator, command)

    assert_receive {:vxpipe_capability_tool_started, ^coordinator, ^command,
                    %Call{id: "tool-real", name: "test_agent_tool"} = call},
                   2_000

    assert_receive {:vxpipe_capability_tool_completed, ^coordinator, ^command, ^call,
                    %{"value" => "checked"}},
                   2_000

    assert_receive {:vxpipe_capability_text, ^coordinator, ^command,
                    "The host action completed."},
                   2_000

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}, 2_000

    completed_identity = {command.connection_id, command.correlation_id, command.id}
    assert {:ok, []} = AgentCoordinator.interrupt(coordinator, [completed_identity])
  end

  test "serializes a background completion after active caller work as engine context" do
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)

    activation_id = "act-background-coordinator-#{System.unique_integer([:positive])}"

    background_supervisor =
      start_supervised!({BackgroundSupervisor, activation_id: activation_id, maximum_children: 1})

    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: activation_id,
         tools: [TestBlockingTool],
         maximum_result_bytes: 4_096,
         maximum_background_tools: 1,
         background_tool_timeout_ms: 1_000,
         background_supervisor: background_supervisor,
         completion_target: self()}
      )

    coordinator = start_coordinator(tool_dispatcher: dispatcher)
    kickoff = command("background-kickoff", "prepare the report")

    assert :ok = AgentCoordinator.respond(coordinator, kickoff)
    assert_receive {:test_agent_request, ^coordinator, kickoff_request, _, kickoff_options}

    tool_context = Keyword.fetch!(kickoff_options, :tool_context)
    guardrail = Map.fetch!(tool_context, :__tool_guardrail_callback__)

    assert :ok =
             guardrail.(%{
               tool_call_id: "tool-background",
               tool_name: "wait_for_test",
               arguments: %{}
             })

    assert {:ok, acknowledgement} =
             Dispatcher.submit(
               dispatcher,
               "wait_for_test",
               %{},
               Map.fetch!(tool_context, :vxpipe_tool_context)
             )

    assert_receive {:test_blocking_tool_started, worker}

    emit(
      coordinator,
      kickoff_request,
      :tool_started,
      %{
        tool_call_id: "tool-background",
        tool_name: "wait_for_test",
        arguments: %{}
      },
      tool_call_id: "tool-background",
      tool_name: "wait_for_test"
    )

    assert_receive {:vxpipe_capability_tool_started, ^coordinator, ^kickoff,
                    %Call{id: "tool-background"} = call}

    emit(
      coordinator,
      kickoff_request,
      :tool_completed,
      %{
        tool_call_id: "tool-background",
        tool_name: "wait_for_test",
        result: {:ok, acknowledgement, []}
      },
      tool_call_id: "tool-background",
      tool_name: "wait_for_test"
    )

    assert_receive {:vxpipe_capability_tool_accepted, ^coordinator, ^kickoff, ^call,
                    ^acknowledgement}

    refute_receive {:vxpipe_capability_tool_completed, ^coordinator, ^kickoff, ^call, _result}

    emit(coordinator, kickoff_request, :request_completed, %{result: "Report started."})
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^kickoff}

    active = command("caller-while-tool-runs", "what else can you do?")
    assert :ok = AgentCoordinator.respond(coordinator, active)
    assert_receive {:test_agent_request, ^coordinator, active_request, _, _options}

    assert {:ok, [^active]} = AgentCoordinator.interrupt(coordinator, [])
    assert_receive {:test_agent_cancel, ^coordinator, ^active_request, :interrupted}

    replacement = command("caller-after-interruption", "continue with this instead")
    assert :ok = AgentCoordinator.respond(coordinator, replacement)
    assert_receive {:test_agent_request, ^coordinator, replacement_request, _, _options}

    send(worker, :release_test_tool)

    assert_receive {:vxpipe_background_tool_finished, ^dispatcher, completion}
    GenServer.cast(coordinator, {:vxpipe_background_tool_finished, dispatcher, completion})

    assert_receive {:vxpipe_capability_tool_completed, ^coordinator, ^kickoff, ^call,
                    %{"released" => true}}

    refute_receive {:test_agent_request, ^coordinator, _request, _query, _options}

    emit(coordinator, active_request, :request_completed, %{result: "stale"})
    refute_receive {:vxpipe_capability_text, ^coordinator, ^active, "stale"}

    emit(coordinator, replacement_request, :request_completed, %{
      result: "I can keep talking."
    })

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^replacement}

    assert_receive {:vxpipe_capability_continuation_started, ^coordinator,
                    %ContinueAgent{} = continuation}

    assert continuation.tool_call_id == "tool-background"
    assert continuation.source_command_id == kickoff.id

    assert_receive {:test_agent_request, ^coordinator, continuation_request, query,
                    continuation_options}

    assert query =~ "tool-background"
    assert query =~ "released"

    assert continuation_options
           |> Keyword.fetch!(:extra_refs)
           |> Map.fetch!(:vxpipe_origin) == :engine

    emit(coordinator, continuation_request, :request_completed, %{result: "The report is ready."})

    assert_receive {:vxpipe_capability_text, ^coordinator, ^continuation, "The report is ready."}

    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^continuation}
    refute_receive {:test_agent_request, ^coordinator, _request, _query, _options}
  end

  defp start_coordinator(overrides \\ []) do
    activation_id = "act-#{System.unique_integer([:positive])}"

    dispatcher =
      start_supervised!(
        {Dispatcher, activation_id: activation_id, tools: [], maximum_result_bytes: 4_096}
      )

    options =
      Keyword.merge(
        [
          activation_id: activation_id,
          agent_participant_id: "agent-test",
          agent_server: self(),
          agent_runtime: TestAgentRuntime,
          owner: self(),
          tool_dispatcher: dispatcher,
          maximum_output_bytes: 65_536,
          maximum_pending_requests: 2,
          request_options: [],
          request_timeout_ms: 1_000
        ],
        overrides
      )

    start_supervised!({AgentCoordinator, options})
  end

  defp command(correlation_id, content) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: "room-test",
               incarnation_id: "rinc-test",
               participant_id: "participant-test",
               connection_id: "connection-test",
               correlation_id: correlation_id,
               content: content,
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp emit(coordinator, request_id, kind, data, options \\ []) do
    seq = Keyword.get_lazy(options, :seq, fn -> next_event_sequence(request_id) end)

    event =
      Event.new(%{
        seq: seq,
        run_id: request_id,
        request_id: request_id,
        iteration: 1,
        kind: kind,
        llm_call_id: Keyword.get(options, :llm_call_id),
        tool_call_id: Keyword.get(options, :tool_call_id),
        tool_name: Keyword.get(options, :tool_name),
        data: data
      })

    send(coordinator, {:jido_ai_request_event, event})
  end

  defp next_event_sequence(request_id) do
    key = {__MODULE__, :event_sequence, request_id}
    sequence = Process.get(key, 0) + 1
    Process.put(key, sequence)
    sequence
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
