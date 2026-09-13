defmodule Vxpipe.CallEngine.AgentRuntime.ContextCompactionRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.ModelResponse
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff}
  alias Vxpipe.CallEngine.Archive.Supervisor, as: ArchiveSupervisor
  alias Vxpipe.CallEngine.CallVariables.BaselineSnapshot
  alias Vxpipe.CallEngine.TestArchiveWriter

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    DefinitionCompiler,
    TestAgentRuntimeInputTokenCounter,
    TestAgentRuntimeModelProvider
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.AgentTurnCompleted

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:implementation, :agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())
      |> Keyword.put(
        :context_compaction,
        enabled: true,
        context_window_tokens: 1_000,
        output_reserve_tokens: 200,
        recent_entries: 1,
        input_token_counter: {TestAgentRuntimeInputTokenCounter, self()},
        input_token_timeout_ms: 1_000,
        compactor_timeout_ms: 1_000
      )

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(original, :agent_runtime, agent_runtime)
    )

    on_exit(fn ->
      Application.put_env(:vxpipe_call_engine, Vxpipe.CallEngine.Application, original)
    end)

    :ok
  end

  test "caller input queued during compaction runs afterward with compacted history" do
    plan = compile_plan()
    connection_id = unique_id("conn-compaction")
    handoff = open_archive()
    {room, caller} = start_room(plan, connection_id, archive_handoff: handoff)
    assert_receive {:test_archive_write, baseline_writer, %BaselineSnapshot{}}
    send(baseline_writer, {:test_archive_write_result, :ok})

    first = send_text(plan, room, caller, connection_id, "first request")
    assert_count(500)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    reply(provider, "first response")
    assert_turn_completed(first)

    second = send_text(plan, room, caller, connection_id, "second request")
    assert_count(500)
    assert_receive {:test_agent_runtime_stream, provider, _request}
    reply(provider, "second response")
    assert_turn_completed(second)

    third = send_text(plan, room, caller, connection_id, "third request")
    assert_count(700)

    assert_receive {:test_agent_runtime_input_count, counter, protected_request}
    refute Enum.any?(protected_request.messages, &(&1.content == "first request"))
    send(counter, {:test_agent_runtime_input_tokens, 300})

    assert_receive {:test_agent_runtime_generate, compactor, summary_request}
    assert summary_request.tools == []
    assert summary_request.pending_invocations == []
    assert summary_request.model_context == %{}

    fourth =
      send_text(plan, room, caller, connection_id, "queued fourth request",
        run_immediately: false
      )

    summary = "The caller completed the first request."

    reply(compactor, summary,
      usage: %{input_tokens: 40, output_tokens: 9, total_tokens: 49},
      provider_metadata: %{request_id: "compaction-request-1"}
    )

    assert_receive {:test_agent_runtime_input_count, counter, compacted_request}
    assert Enum.any?(compacted_request.messages, &(&1.origin == :derived_summary))
    send(counter, {:test_agent_runtime_input_tokens, 350})

    assert_receive {:test_agent_runtime_stream, provider, third_request}
    assert Enum.any?(third_request.messages, &(&1.origin == :derived_summary))
    assert List.last(third_request.messages).content == third.content
    reply(provider, "third response")
    assert_turn_completed(third)

    assert_count(500)
    assert_receive {:test_agent_runtime_stream, provider, fourth_request}
    assert Enum.any?(fourth_request.messages, &(&1.origin == :derived_summary))
    assert List.last(fourth_request.messages).content == fourth.content
    reply(provider, "fourth response")
    assert_turn_completed(fourth)

    facts = collect_through_compaction_usage(handoff, [])
    assert Enum.any?(facts, &accepted_first_request?/1)
    assert Enum.any?(facts, &generated_first_response?/1)
    refute Enum.any?(facts, &(inspect(&1.payload) =~ summary))
  end

  defp compile_plan do
    input = %{
      schema_version: "20260913.01",
      entry_caller: "caller",
      entry_receiver: "receiver",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "receiver" => %{
          type: "agent",
          prompt: "Help the caller.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{},
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }

    assert {:ok, definition} =
             CallDefinition.new(input, resource_id: "compaction-definition", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "compaction-definition", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               call_id: unique_id("call"),
               room_id: unique_id("room")
             )

    registries = %{
      capability_profiles: %{
        "test-model" => %{
          kind: :model_inference,
          provider: :req_llm,
          options: %{model: "test:scripted"}
        }
      },
      host_tools: %{}
    }

    assert {:ok, plan} = DefinitionCompiler.compile(definition, invocation, registries)
    plan
  end

  defp start_room(plan, connection_id, options) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, room} = CallEngine.start_call(plan, options)

    assert {:ok, command} =
             AttachConnection.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               deadline: future_deadline()
             )

    assert {:ok, _attachment} = CallEngine.attach_connection(command)
    {room, caller}
  end

  defp send_text(plan, room, caller, connection_id, content, options \\ []) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: plan.tenant_id,
               actor_id: plan.actor_id,
               room_id: plan.room_id,
               incarnation_id: room.incarnation_id,
               participant_id: caller.participant_id,
               connection_id: connection_id,
               correlation_id: unique_id("turn"),
               content: content,
               run_immediately: Keyword.get(options, :run_immediately, true),
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)
    command
  end

  defp assert_count(tokens) do
    assert_receive {:test_agent_runtime_input_count, counter, _request}
    send(counter, {:test_agent_runtime_input_tokens, tokens})
  end

  defp reply(provider, text, options \\ []) do
    assert {:ok, response} =
             ModelResponse.new(
               text: text,
               usage: Keyword.get(options, :usage, %{}),
               provider_metadata: Keyword.get(options, :provider_metadata, %{})
             )

    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp open_archive do
    assert {:ok, handoff} =
             ArchiveSupervisor.open(
               writer: {TestArchiveWriter, self()},
               maximum_pending_facts: 64,
               retry_delay_ms: 5,
               drain_timeout_ms: 1_000
             )

    on_exit(fn ->
      if Process.alive?(handoff.subscriber) do
        Handoff.source_stopped(handoff, :test_cleanup)
      end
    end)

    handoff
  end

  defp collect_through_compaction_usage(handoff, facts) do
    receive do
      {:test_archive_fact,
       %Fact{
         kind: :usage_observed,
         payload: %{
           "measurement" => %{"component" => "context_compaction_total_tokens"}
         }
       } = fact} ->
        Enum.reverse([fact | facts])

      {:test_archive_fact, %Fact{} = fact} ->
        collect_through_compaction_usage(handoff, [fact | facts])
    after
      2_000 ->
        evidence =
          facts
          |> Enum.reverse()
          |> Enum.map(fn fact ->
            {fact.kind, get_in(fact.payload, ["measurement", "component"])}
          end)

        flunk("timed out waiting for archived compaction usage: #{inspect(evidence)}")
    end
  end

  defp accepted_first_request?(%Fact{
         kind: :accepted_input,
         payload: %{"content" => "first request"}
       }),
       do: true

  defp accepted_first_request?(%Fact{}), do: false

  defp generated_first_response?(%Fact{
         kind: :agent_output_generated,
         payload: %{"text" => "first response"}
       }),
       do: true

  defp generated_first_response?(%Fact{}), do: false

  defp assert_turn_completed(command) do
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}

    assert correlation_id == command.correlation_id
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
