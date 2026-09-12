defmodule Vxpipe.CallEngine.AgentRuntime.ContextCompactionRoomTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.ModelResponse
  alias Vxpipe.CallEngine

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
    {room, caller} = start_room(plan, connection_id)

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

    reply(compactor, "The caller completed the first request.")

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
  end

  defp compile_plan do
    input = %{
      schema_version: "20260911.03",
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

  defp start_room(plan, connection_id) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    assert {:ok, room} = CallEngine.start_call(plan)

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

  defp reply(provider, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_turn_completed(command) do
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}

    assert correlation_id == command.correlation_id
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
