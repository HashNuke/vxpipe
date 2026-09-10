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
  alias Vxpipe.CallEngine.Archive.Fact
  alias Vxpipe.CallEngine.CallVariables.UpdateSnapshot
  alias Vxpipe.CallEngine.Provider.Deepgram.FluxTextToSpeech
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

  test "speaks the acknowledgement while a non-blocking remote invocation remains pending" do
    configure_text_to_speech()
    observer = self()
    remote_result = {:ok, %{"content" => [%{"type" => "text", "text" => "Customer found."}]}}

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, remote_result}], invocations: []} end}
      )

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-speaking-sentinel")

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store, speech: true)

    assert {:ok, room} =
             CallEngine.start_call(plan,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    assert_receive {:test_tts_transport_started, tts_transport, _connection}
    sink = start_supervised!({Vxpipe.CallEngine.TestAudioOutputSink, observer: self()})
    {caller, connection_id} = attach_caller(plan, room, sink)

    initial =
      send_text(plan, room, caller, connection_id, "Find the customer.", audio_response: true)

    assert_receive {:test_agent_runtime_stream, provider, _initial_request}
    reply_with_tool(provider, "remote-speaking")
    assert_receive {:test_remote_mcp_invocation_started, execution}

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert_pending(acknowledgement, "remote-speaking")
    reply_with_text(acknowledgement_provider, "I am checking the customer.")

    complete_spoken_output(
      tts_transport,
      sink,
      "I am checking the customer.",
      "speech-acknowledgement"
    )

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}
    assert correlation_id == initial.correlation_id
    refute_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "remote-speaking"}}, 50

    send(execution, :release_test_remote_mcp)
    assert_receive {:vxpipe_event, %ToolCallCompleted{tool_call_id: "remote-speaking"}}
    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "I found the customer.")

    complete_spoken_output(
      tts_transport,
      sink,
      "I found the customer.",
      "speech-completion"
    )
  end

  test "archives a scoped remote result before an authorized variables update" do
    observer = self()
    remote_result = %{"content" => [%{"type" => "text", "text" => "Customer found."}]}

    client =
      start_supervised!(
        {Agent,
         fn ->
           %{responses: [{:wait, observer, {:ok, remote_result}}], invocations: []}
         end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, _binding} =
      RemoteMCPFixture.binding!(client, self(), "private-history-sentinel",
        credential_generation: generation
      )

    store = start_supervised!({CatalogStore, catalog: integrations})
    plan = compile_plan(store, variables: true)

    archive = [
      enabled: true,
      writer: {Vxpipe.CallEngine.TestCollectingArchiveWriter, self()},
      maximum_pending_facts: 64,
      retry_delay_ms: 5,
      drain_timeout_ms: 1_000
    ]

    assert {:ok, room} =
             CallEngine.start_call(plan,
               archive: archive,
               mcp_catalog_store: store,
               remote_mcp_connection_provider: TestRemoteMCPConnectionProvider,
               remote_mcp_protocol_client: TestRemoteMCPProtocolClient
             )

    {caller, connection_id} = attach_caller(plan, room)
    initial = send_text(plan, room, caller, connection_id, "Find and save the customer.")

    assert_receive {:test_agent_runtime_stream, remote_provider, remote_request}

    assert Enum.map(remote_request.tools, & &1.name) == [
             "customer_lookup",
             "read_variables",
             "update_variable",
             "update_variables"
           ]

    reply_with_tool(remote_provider, "remote-history")
    assert_receive {:test_remote_mcp_invocation_started, remote_execution}
    assert_receive {:vxpipe_event, %ToolCallStarted{tool_call_id: "remote-history"}}

    assert_receive {:test_agent_runtime_stream, remote_ack_provider, remote_ack_request}
    assert_pending(remote_ack_request, "remote-history")
    reply_with_text(remote_ack_provider, "I am checking the customer.")
    send(remote_execution, :release_test_remote_mcp)

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "remote-history",
                      name: "customer_lookup",
                      result: ^remote_result
                    }}

    assert_receive {:test_agent_runtime_stream, variables_provider, variables_request}
    assert List.last(variables_request.messages).origin == :engine

    reply_with_tool(
      variables_provider,
      "save-customer",
      "update_variables",
      %{
        "section_name" => "customer",
        "data" => %{"customer_id" => "customer-42", "status" => "found"},
        "expected_revision" => 0
      }
    )

    assert_receive {:vxpipe_event,
                    %ToolCallCompleted{
                      tool_call_id: "save-customer",
                      name: "update_variables",
                      result: %{
                        "section" => "customer",
                        "revision" => 1,
                        "value" => %{
                          "customer_id" => "customer-42",
                          "status" => "found"
                        }
                      }
                    }}

    assert_receive {:test_agent_runtime_stream, variables_ack_provider, variables_ack_request}
    assert variables_ack_request.tools == []
    reply_with_text(variables_ack_provider, "I am saving the customer.")

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine
    reply_with_text(completion_provider, "The customer is saved.")

    assert_receive {:vxpipe_event, %AgentTurnCompleted{correlation_id: correlation_id}}
    assert correlation_id == initial.correlation_id

    assert [remote_invocation] = Agent.get(client, & &1.invocations)
    assert remote_invocation.name == "lookup_customer"
    assert remote_invocation.arguments == %{"customer_id" => "customer-42"}
    assert Map.keys(remote_invocation) |> Enum.sort() == [:arguments, :name, :timeout]

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :tool_call_started,
                      tool_call_id: "remote-history",
                      payload: %{
                        "name" => "customer_lookup",
                        "arguments" => %{"customer_id" => "customer-42"}
                      }
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %Fact{
                      kind: :tool_call_completed,
                      tool_call_id: "remote-history",
                      payload: %{"name" => "customer_lookup", "result" => ^remote_result}
                    }},
                   2_000

    assert_receive {:test_archive_fact,
                    %UpdateSnapshot{
                      participant_id: participant_id,
                      tool_call_id: "save-customer",
                      section: "customer",
                      section_revision: 1,
                      sections: %{
                        "customer" => %{
                          revision: 1,
                          value: %{"customer_id" => "customer-42", "status" => "found"}
                        }
                      }
                    }},
                   2_000

    reception = Map.fetch!(plan.participants, "reception")
    assert participant_id == reception.participant_id
    refute inspect(remote_invocation) =~ "private-history-sentinel"
  end

  defp compile_plan(store, options \\ []) do
    assert {:ok, definition} =
             CallDefinition.new(definition_input(options),
               resource_id: "remote-live",
               revision: 1
             )

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
        },
        "test-voice" => %{
          kind: :text_to_speech,
          provider: FluxTextToSpeech,
          options: %{model: "flux-plan-voice", encoding: :linear16, sample_rate: 48_000}
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

  defp definition_input(options) do
    {call_variables, variable_permissions} = variables_definition(options)

    receiver_capabilities =
      %{model_inference: "test-model"}
      |> maybe_enable_speech(options)

    %{
      schema_version: CallDefinition.schema_version(),
      entry_caller: "caller",
      entry_receiver: "reception",
      defaults: %{capabilities: %{}},
      call_variables: call_variables,
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
          capabilities: receiver_capabilities,
          tools: %{
            "customer_lookup" => %{
              type: "mcp",
              integration: "records",
              tool: "lookup_customer",
              conversation_mode: "non_blocking"
            }
          },
          variable_permissions: variable_permissions,
          transfers: []
        }
      },
      limits: %{max_duration_ms: 60_000}
    }
  end

  defp maybe_enable_speech(capabilities, options) do
    if Keyword.get(options, :speech, false) do
      Map.put(capabilities, :text_to_speech, "test-voice")
    else
      capabilities
    end
  end

  defp variables_definition(options) do
    if Keyword.get(options, :variables, false) do
      sections = %{
        "customer" => %{
          schema: %{
            "type" => "object",
            "properties" => %{
              "customer_id" => %{"type" => "string"},
              "status" => %{"type" => "string"}
            },
            "additionalProperties" => false
          }
        }
      }

      {%{sections: sections}, %{"customer" => ["read", "write"]}}
    else
      {%{sections: %{}}, %{}}
    end
  end

  defp attach_caller(plan, room, output_sink \\ nil) do
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

    assert {:ok, _attachment} = CallEngine.attach_connection(command, output_sink)
    {caller, connection_id}
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
               audio_response: Keyword.get(options, :audio_response, false),
               deadline: future_deadline()
             )

    assert :ok = CallEngine.send_text(command)
    command
  end

  defp reply_with_tool(provider, id) do
    reply_with_tool(provider, id, "customer_lookup", %{"customer_id" => "customer-42"})
  end

  defp reply_with_tool(provider, id, name, arguments) do
    assert {:ok, call} =
             ToolCall.new(
               id: id,
               name: name,
               arguments: arguments
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

  defp complete_spoken_output(tts_transport, sink, expected_text, speech_id) do
    assert_receive {:test_tts_control, ^tts_transport, speak}, 2_000
    assert JSON.decode!(speak) == %{"text" => expected_text, "type" => "Speak"}
    assert_receive {:test_tts_control, ^tts_transport, flush}, 2_000
    assert JSON.decode!(flush) == %{"type" => "Flush"}

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{"type" => "SpeechStarted", "request_id" => "req", "speech_id" => speech_id})
    )

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_audio(tts_transport, <<1, 0, 2, 0>>)
    assert_receive {:test_audio_output, ^sink, _frame}, 2_000

    Vxpipe.CallEngine.TestTextToSpeechTransport.deliver_control(
      tts_transport,
      JSON.encode!(%{"type" => "SpeechMetadata", "request_id" => "req", "speech_id" => speech_id})
    )

    assert_receive {:test_audio_output_finish, ^sink, _turn_id}, 2_000
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_started(sink)
    :ok = Vxpipe.CallEngine.TestAudioOutputSink.playback_completed(sink)
  end

  defp configure_text_to_speech do
    settings = Application.fetch_env!(:vxpipe_call_engine, Vxpipe.CallEngine.Application)

    text_to_speech = [
      enabled: true,
      provider: FluxTextToSpeech,
      provider_options: [
        api_key: "test-runtime-secret",
        model: "flux-application-voice",
        encoding: :linear16,
        sample_rate: 48_000
      ],
      transport: {Vxpipe.CallEngine.TestTextToSpeechTransport, [observer: self()]},
      maximum_requests: 4
    ]

    Application.put_env(
      :vxpipe_call_engine,
      Vxpipe.CallEngine.Application,
      Keyword.put(settings, :text_to_speech, text_to_speech)
    )
  end

  defp future_deadline, do: DateTime.add(DateTime.utc_now(), 5, :second)
  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
