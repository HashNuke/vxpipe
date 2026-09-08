defmodule Vxpipe.CallEngine.AgentCoordinatorTest do
  use ExUnit.Case, async: false

  import Jido.AI.Test

  alias Jido.AI.Runtime.Event
  alias Vxpipe.CallEngine.Agent
  alias Vxpipe.CallEngine.AgentCoordinator
  alias Vxpipe.CallEngine.AgentFactory
  alias Vxpipe.CallEngine.JidoAgentRuntime
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.TestAgentTool
  alias Vxpipe.CallEngine.TestAgentRuntime
  alias Vxpipe.CallEngine.Tool.Call
  alias Vxpipe.CallEngine.Tool.Dispatcher

  test "projects streamed sentences and one tool lifecycle onto the existing contract" do
    coordinator = start_coordinator()
    command = command("stream-tool", "check a value")

    assert :ok = AgentCoordinator.respond(coordinator, command)
    assert_receive {:test_agent_request, ^coordinator, request_id, "check a value", options}
    assert Keyword.fetch!(options, :stream_to) == {:pid, coordinator}

    assert Keyword.fetch!(options, :request_transformer) ==
             Vxpipe.CallEngine.AgentRequestTransformer

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
end
