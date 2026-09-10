defmodule Vxpipe.CallEngine.RemoteMCP.LiveCallTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, PendingInvocation, ToolCall}
  alias Vxpipe.CallEngine

  alias Vxpipe.CallEngine.{
    CallDefinition,
    CallInvocation,
    RemoteMCPFixture,
    Error,
    TestAgentRuntimeModelProvider,
    TestRemoteMCPConnectionProvider,
    TestRemoteMCPProtocolClient
  }

  alias Vxpipe.CallEngine.Command.{AttachConnection, SendText}
  alias Vxpipe.CallEngine.Event.{AgentTurnCompleted, ToolCallCompleted, ToolCallStarted}
  alias Vxpipe.CallEngine.RemoteMCP.{CatalogStore, IntegrationCatalog}

  setup do
    original = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    agent_runtime =
      original
      |> Keyword.fetch!(:agent_runtime)
      |> Keyword.put(:model_provider, TestAgentRuntimeModelProvider)
      |> Keyword.put(:model_provider_options, owner: self())

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

  test "runs a tenant MCP tool while an explicitly non-blocking conversation continues" do
    observer = self()
    result = {:ok, %{"content" => [%{"type" => "text", "text" => "Customer found."}]}}

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, result}], invocations: []} end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-live-call-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    assert_receive {:test_remote_mcp_opened, _key, opened_config}
    assert opened_config[:private] == "private-live-call-sentinel"

    {caller, connection_id} = attach_caller(plan, room)
    initial = send_text(plan, room, caller, connection_id, "Find the customer.")

    assert_receive {:test_agent_runtime_stream, provider, initial_request}
    assert Enum.map(initial_request.tools, & &1.name) == ["customer_lookup"]
    refute inspect(initial_request) =~ "private-live-call-sentinel"
    refute inspect(initial_request) =~ "lookup_customer"

    reply_with_tool(provider, "remote-live-call")

    assert_receive {:test_remote_mcp_invocation_started, execution}
    refute execution == provider
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "remote-live-call"}}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert_pending(acknowledgement, "remote-live-call")
    reply_with_text(acknowledgement_provider, "I am checking now.")
    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: initial_correlation}}
    assert initial_correlation == initial.correlation_id

    unrelated = send_text(plan, room, caller, connection_id, "What can we discuss meanwhile?")

    assert_receive {:test_agent_runtime_stream, unrelated_provider, unrelated_request}
    assert List.last(unrelated_request.messages).content == unrelated.content
    assert_pending(unrelated_request, "remote-live-call")
    reply_with_text(unrelated_provider, "We can discuss your account options.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: unrelated_correlation}}
    assert unrelated_correlation == unrelated.correlation_id

    send(execution, :release_test_remote_mcp)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "remote-live-call",
                      name: "customer_lookup",
                      result: %{"content" => [%{"type" => "text", "text" => "Customer found."}]}
                    }}

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "I found the customer.")
  end

  test "rejects a pinned remote generation replaced before room startup" do
    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(self(), self(), "private-stale-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store)
    assert {:ok, empty} = IntegrationCatalog.new(application: %{}, tenants: %{})
    assert :ok = CatalogStore.publish(store, empty)

    assert {:error,
            %Error{
              code: :unsupported_call_plan,
              details: %{
                "path" => ["participants", "reception", "tools", "customer_lookup"],
                "reason" => "pinned remote MCP generation is no longer available"
              }
            }} = CallEngine.start_call(plan, mcp_catalog_store: store)

    assert Registry.lookup(Vxpipe.CallEngine.RoomRegistry, {plan.tenant_id, plan.room_id}) == []
  end

  defp compile_plan(store) do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(), resource_id: "remote-live", revision: 1)

    assert {:ok, invocation} =
             CallInvocation.new(
               %{
                 call_definition: %{id: "remote-live", revision: 1},
                 initial_variables: %{},
                 transport: %{type: "web"}
               },
               tenant_id: "tenant-demo",
               actor_id: "actor-demo",
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

    assert {:ok, plan} =
             CallEngine.compile_definition(definition, invocation, registries,
               mcp_catalog_store: store
             )

    plan
  end

  defp definition_input do
    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{}},
      call_variables: %{sections: %{}},
      participants: %{
        "caller" => %{
          type: "human",
          connection: %{service: "web", mode: "receive", admission: "start_call"},
          capabilities: %{}
        },
        "reception" => %{
          type: "agent",
          prompt: "Use the available customer tool.",
          first_message: %{mode: "wait_for_input"},
          capabilities: %{model_inference: "test-model"},
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              tool: "lookup_customer",
              conversation_mode: "non_blocking"
            }
          },
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp attach_caller(plan, room) do
    caller = Map.fetch!(plan.participants, plan.entry_caller)
    connection_id = unique_id("connection")

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
    {caller, connection_id}
  end

  defp send_text(plan, room, caller, connection_id, content) do
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
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)
    command
  end

  defp reply_with_tool(provider, id) do
    assert {:ok, call} =
             ToolCall.new(
               id: id,
               name: "customer_lookup",
               arguments: %{"customer_id" => "customer-42"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp reply_with_text(provider, text) do
    assert {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp assert_pending(request, invocation_id) do
    assert [
             %PendingInvocation{
               invocation_id: ^invocation_id,
               tool_name: "customer_lookup",
               conversation_mode: :non_blocking,
               status: :running
             }
           ] = request.pending_invocations

    assert Enum.count(request.messages, fn
             %Message{role: :tool, tool_call_id: ^invocation_id, content: content} ->
               JSON.decode!(content) == %{
                 "invocation_id" => invocation_id,
                 "status" => "running"
               }

             _message ->
               false
           end) == 1
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
