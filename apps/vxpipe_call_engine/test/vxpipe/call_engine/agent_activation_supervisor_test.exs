defmodule Vxpipe.CallEngine.AgentActivationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.AgentActivationSupervisor
  alias Vxpipe.CallEngine.AgentRuntime.{Coordinator, ToolDescriptors}
  alias Vxpipe.CallEngine.Command.SendText
  alias Vxpipe.CallEngine.RemoteMCP.{Integration, IntegrationCatalog}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Usage.ProviderContext

  alias Vxpipe.CallEngine.{
    RemoteMCPFixture,
    TestAgentRuntimeModelProvider,
    TestAgentTool,
    TestBlockingTool,
    TestRemoteMCPConnectionProvider,
    TestRemoteMCPProtocolClient
  }

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationRegistry
  }

  alias Vxpipe.AgentRuntime.{Message, ModelResponse, ToolCall}
  alias Vxpipe.MCP.Catalog

  setup do
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer)
    end)
  end

  test "owns one complete Agent Runtime activation graph" do
    activation_id = unique_activation_id()

    activation =
      start_supervised!({AgentActivationSupervisor, agent_runtime_options(activation_id)})

    first = AgentActivationSupervisor.children(activation)

    assert Map.keys(first) |> Enum.sort() == [
             :coordinator,
             :invocation_registry,
             :invocation_supervisor,
             :request_supervisor,
             :session
           ]

    assert Enum.all?(first, fn {_role, pid} -> is_pid(pid) end)

    assert :ok =
             Coordinator.respond(
               Map.fetch!(first, :coordinator),
               send_text("agent-runtime-activation")
             )

    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [%Message{role: :system, content: "Use only the selected action."} | _history] =
             request.messages

    assert Enum.map(request.tools, & &1.name) == ["test_agent_tool"]

    assert {:ok, response} = ModelResponse.new(text: "Ready from Agent Runtime.")
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:vxpipe_capability_text, coordinator, command, "Ready from Agent Runtime."}
    assert coordinator == Map.fetch!(first, :coordinator)
    assert command.correlation_id == "agent-runtime-activation"
    assert_receive {:vxpipe_capability_text_complete, ^coordinator, ^command}

    monitors = monitor_children(first)
    Process.exit(Map.fetch!(first, :session), :kill)
    assert_children_stopped(monitors)

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)

    assert Enum.all?(second, fn {role, pid} ->
             is_pid(pid) and pid != Map.fetch!(first, role)
           end)

    restarted_monitors = monitor_children(second)
    activation_monitor = Process.monitor(activation)
    Process.exit(Map.fetch!(second, :session), :kill)

    assert_receive {:DOWN, ^activation_monitor, :process, ^activation, _reason}, 1_000
    assert_children_stopped(restarted_monitors)
  end

  test "a failed readiness configuration leaves no registered activation children" do
    activation_id = unique_activation_id()

    invalid_tool = %ToolBinding{
      name: "test_agent_tool",
      type: :host,
      conversation_mode: :blocking,
      action: String,
      remote: nil
    }

    invalid =
      Keyword.put(agent_runtime_options(activation_id), :tools, %{
        "test_agent_tool" => invalid_tool
      })

    assert {:error, _reason} = start_supervised({AgentActivationSupervisor, invalid})

    assert AgentActivationSupervisor.whereis_child(activation_id, :coordinator) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :session) == nil
    assert AgentActivationSupervisor.whereis_child(activation_id, :invocation_supervisor) == nil
  end

  test "replacement discards an in-flight worker and ignores its stale completion" do
    activation_id = unique_activation_id()

    activation =
      start_supervised!({AgentActivationSupervisor, blocking_tool_options(activation_id)})

    first = AgentActivationSupervisor.children(activation)
    coordinator = Map.fetch!(first, :coordinator)

    assert :ok = Coordinator.respond(coordinator, send_text("stale-tool-activation"))
    assert_receive {:test_agent_runtime_stream, provider, _request}

    assert {:ok, call} =
             ToolCall.new(id: "stale-tool-call", name: "wait_for_test", arguments: %{})

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_blocking_tool_started, execution}

    assert [{_id, invocation_worker, :worker, _modules}] =
             DynamicSupervisor.which_children(Map.fetch!(first, :invocation_supervisor))

    first_monitors = monitor_children(first)
    execution_monitor = Process.monitor(execution)
    Process.exit(Map.fetch!(first, :session), :kill)

    assert_children_stopped(first_monitors)
    assert_receive {:DOWN, ^execution_monitor, :process, ^execution, _reason}, 1_000

    _ = :sys.get_state(activation)
    second = AgentActivationSupervisor.children(activation)
    replacement_registry = Map.fetch!(second, :invocation_registry)

    stale_completion = %InvocationCompletion{
      invocation_id: "stale-tool-call",
      tool_name: "wait_for_test",
      conversation_mode: :blocking,
      context: stale_context(),
      outcome: {:ok, %{"released" => true}}
    }

    send(
      replacement_registry,
      {:vxpipe_tool_invocation_finished, invocation_worker, stale_completion}
    )

    _ = :sys.get_state(replacement_registry)
    assert {:ok, []} = InvocationRegistry.snapshot(replacement_registry)
  end

  test "owns and executes a private remote MCP binding in the Agent Runtime graph" do
    observer = self()
    remote_result = {:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}

    client =
      start_supervised!(
        {Agent,
         fn ->
           %{responses: [{:wait, observer, remote_result}], invocations: []}
         end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, remote_binding} =
      RemoteMCPFixture.binding!(client, self(), "private-remote-sentinel",
        credential_generation: generation
      )

    activation_id = unique_activation_id()

    options =
      activation_id
      |> agent_runtime_options()
      |> Keyword.put(:tools, %{"customer_lookup" => remote_binding})
      |> Keyword.put(:mcp_integrations, integrations)
      |> Keyword.put(:remote_mcp_connection_provider, TestRemoteMCPConnectionProvider)
      |> Keyword.put(:remote_mcp_protocol_client, TestRemoteMCPProtocolClient)

    activation = start_supervised!({AgentActivationSupervisor, options})
    children = AgentActivationSupervisor.children(activation)

    assert Map.has_key?(children, :remote_mcp_owner)
    assert_receive {:test_remote_mcp_opened, _key, opened_config}
    assert opened_config[:private] == "private-remote-sentinel"
    refute inspect(:sys.get_state(activation)) =~ "private-remote-sentinel"

    coordinator = Map.fetch!(children, :coordinator)
    assert :ok = Coordinator.respond(coordinator, send_text("remote-mcp-activation"))
    assert_receive {:test_agent_runtime_stream, provider, request}

    assert [tool] = request.tools
    assert tool.name == "customer_lookup"
    assert tool.description == "Looks up one customer."
    refute inspect(tool) =~ "lookup_customer"
    refute inspect(request) =~ "private-remote-sentinel"

    assert {:ok, call} =
             ToolCall.new(
               id: "remote-mcp-call",
               name: "customer_lookup",
               arguments: %{"customer_id" => "customer-42"}
             )

    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})

    assert_receive {:test_remote_mcp_invocation_started, execution}
    refute execution == provider

    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert acknowledgement.tools == []

    assert Enum.any?(acknowledgement.messages, fn
             %Message{role: :tool, tool_call_id: "remote-mcp-call", content: content} ->
               content =~ "running"

             _message ->
               false
           end)

    assert {:ok, acknowledgement_response} = ModelResponse.new(text: "I am checking now.")

    send(
      acknowledgement_provider,
      {:test_agent_runtime_response, {:ok, acknowledgement_response}}
    )

    send(execution, :release_test_remote_mcp)

    assert_receive {:test_agent_runtime_stream, completion_provider, completion_request}
    assert List.last(completion_request.messages).origin == :engine

    assert {:ok, completion_response} = ModelResponse.new(text: "Customer found.")
    send(completion_provider, {:test_agent_runtime_response, {:ok, completion_response}})

    assert_receive {:vxpipe_capability_text, ^coordinator, _command, "Customer found."}
  end

  test "uses one Agent Runtime loop for host tools and independently pinned remote aliases" do
    observer = self()

    client =
      start_supervised!(
        {Agent,
         fn ->
           %{
             responses: [
               {:wait, observer, {:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}},
               {:wait, observer,
                {:ok, %{"content" => [%{"type" => "text", "text" => "invoice"}]}}}
             ],
             invocations: []
           }
         end}
      )

    {integrations, remote_bindings} = remote_aliases!(client)
    activation_id = unique_activation_id()

    tools =
      Map.put(
        remote_bindings,
        "test_agent_tool",
        %ToolBinding{
          name: "test_agent_tool",
          type: :host,
          conversation_mode: :blocking,
          action: TestAgentTool,
          remote: nil
        }
      )

    options =
      activation_id
      |> agent_runtime_options()
      |> Keyword.put(:tools, tools)
      |> Keyword.put(:mcp_integrations, integrations)
      |> Keyword.put(:remote_mcp_connection_provider, TestRemoteMCPConnectionProvider)
      |> Keyword.put(:remote_mcp_protocol_client, TestRemoteMCPProtocolClient)
      |> Keyword.put(:maximum_completed_requests, 8)
      |> Keyword.put(:maximum_tool_invocations, 4)

    activation = start_supervised!({AgentActivationSupervisor, options})
    children = AgentActivationSupervisor.children(activation)
    remote_owner = Map.fetch!(children, :remote_mcp_owner)
    coordinator = Map.fetch!(children, :coordinator)

    assert {:ok, private_descriptors} = ToolDescriptors.compile(tools, nil, remote_owner)

    private_descriptors = Map.new(private_descriptors, &{&1.name, &1})
    private_customer = Map.fetch!(private_descriptors, "customer_lookup")
    private_invoice = Map.fetch!(private_descriptors, "invoice_lookup")

    assert %InvocationBinding{handler: {:remote_mcp, ^remote_owner}} = private_customer.binding
    assert %InvocationBinding{handler: {:remote_mcp, ^remote_owner}} = private_invoice.binding

    assert :ok = Coordinator.respond(coordinator, send_text("mixed-runtime-tools"))
    assert_receive {:test_agent_runtime_stream, initial_provider, initial_request}

    assert Enum.map(initial_request.tools, & &1.name) == [
             "customer_lookup",
             "invoice_lookup",
             "test_agent_tool"
           ]

    descriptors = Map.new(initial_request.tools, &{&1.name, &1})
    customer = Map.fetch!(descriptors, "customer_lookup")
    invoice = Map.fetch!(descriptors, "invoice_lookup")

    assert customer.input_schema == customer_schema()
    assert invoice.input_schema == invoice_schema()
    refute inspect(initial_request) =~ "lookup_customer"
    refute inspect(initial_request) =~ "lookup_invoice"
    refute inspect(initial_request) =~ "private-mixed-tools"

    reply_with_tool(initial_provider, "host-call", "test_agent_tool", %{"value" => "local"})
    acknowledge_running("host-call", "test_agent_tool")

    assert_receive {:test_agent_runtime_stream, host_completion_provider, host_completion}
    assert List.last(host_completion.messages).origin == :engine

    reply_with_tool(
      host_completion_provider,
      "customer-call",
      "customer_lookup",
      %{"customer_id" => "customer-42"}
    )

    customer_execution = acknowledge_remote("customer-call", "customer_lookup")
    send(customer_execution, :release_test_remote_mcp)

    assert_receive {:test_agent_runtime_stream, customer_completion_provider, customer_completion}

    assert List.last(customer_completion.messages).origin == :engine

    reply_with_tool(
      customer_completion_provider,
      "invoice-call",
      "invoice_lookup",
      %{"invoice_number" => 42}
    )

    invoice_execution = acknowledge_remote("invoice-call", "invoice_lookup")
    send(invoice_execution, :release_test_remote_mcp)

    assert_receive {:test_agent_runtime_stream, invoice_completion_provider, invoice_completion}
    assert List.last(invoice_completion.messages).origin == :engine

    assert {:ok, final_response} = ModelResponse.new(text: "Both records are ready.")
    send(invoice_completion_provider, {:test_agent_runtime_response, {:ok, final_response}})

    assert_receive {:vxpipe_capability_text, ^coordinator, _command, "Both records are ready."}

    assert [
             %{name: "lookup_customer", arguments: %{"customer_id" => "customer-42"}} =
               customer_invocation,
             %{name: "lookup_invoice", arguments: %{"invoice_number" => 42}} =
               invoice_invocation
           ] = Agent.get(client, & &1.invocations)

    assert customer_invocation.timeout in 1..12_000
    assert invoice_invocation.timeout in 1..12_000
  end

  defp agent_runtime_options(activation_id) do
    assert {:ok, usage_provider} =
             ProviderContext.new(
               name: "test",
               integration_id: "test-model",
               model: "test:scripted"
             )

    [
      runtime: :agent_runtime,
      activation_id: activation_id,
      agent_participant_id: "agent-test",
      call_id: "call-test",
      owner: self(),
      system_prompt: "Use only the selected action.",
      tools: %{
        "test_agent_tool" => %ToolBinding{
          name: "test_agent_tool",
          type: :host,
          conversation_mode: :blocking,
          action: TestAgentTool,
          remote: nil
        }
      },
      variable_binding: nil,
      model_provider: TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      provider: :test,
      usage_provider: usage_provider,
      tool_invocation_timeout_ms: 1_000,
      maximum_completed_requests: 4,
      maximum_tool_invocations: 2,
      maximum_output_bytes: 65_536,
      maximum_pending_requests: 2,
      maximum_tool_result_bytes: 4_096,
      request_timeout_ms: 1_000
    ]
  end

  defp blocking_tool_options(activation_id) do
    Keyword.put(agent_runtime_options(activation_id), :tools, %{
      "wait_for_test" => %ToolBinding{
        name: "wait_for_test",
        type: :host,
        conversation_mode: :blocking,
        action: TestBlockingTool,
        remote: nil
      }
    })
  end

  defp acknowledge_running(invocation_id, tool_name) do
    assert_receive {:test_agent_runtime_stream, acknowledgement_provider, acknowledgement}
    assert acknowledgement.tools == []

    assert Enum.any?(acknowledgement.messages, fn
             %Message{
               role: :tool,
               name: ^tool_name,
               tool_call_id: ^invocation_id,
               content: content
             } ->
               content =~ "running"

             _message ->
               false
           end)

    assert {:ok, response} = ModelResponse.new(text: "I am checking now.")
    send(acknowledgement_provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp acknowledge_remote(invocation_id, tool_name) do
    assert_receive {:test_remote_mcp_invocation_started, execution}
    acknowledge_running(invocation_id, tool_name)
    execution
  end

  defp reply_with_tool(provider, id, name, arguments) do
    assert {:ok, call} = ToolCall.new(id: id, name: name, arguments: arguments)
    assert {:ok, response} = ModelResponse.new(text: "", tool_calls: [call])
    send(provider, {:test_agent_runtime_response, {:ok, response}})
  end

  defp remote_aliases!(client) do
    assert {:ok, catalog} =
             Catalog.new([
               %{
                 "name" => "lookup_customer",
                 "description" => "Looks up one customer.",
                 "inputSchema" => customer_schema()
               },
               %{
                 "name" => "lookup_invoice",
                 "description" => "Looks up one invoice.",
                 "inputSchema" => invoice_schema()
               }
             ])

    assert {:ok, integration} =
             Integration.new(
               integration_id: "records",
               configuration_generation: "configuration-mixed",
               credential_generation: "credential-mixed",
               catalog_generation: "catalog-mixed",
               catalog: catalog,
               allowed_tools: ["lookup_customer", "lookup_invoice"],
               client_config: [
                 test_client: client,
                 test_observer: self(),
                 private: "private-mixed-tools"
               ],
               invocation_deadline_ms: 12_000
             )

    assert {:ok, integrations} =
             IntegrationCatalog.new(
               application: %{},
               tenants: %{"tenant-demo" => %{"records" => integration}}
             )

    bindings = %{
      "customer_lookup" => remote_binding!(integrations, "customer_lookup", "lookup_customer"),
      "invoice_lookup" => remote_binding!(integrations, "invoice_lookup", "lookup_invoice")
    }

    {integrations, bindings}
  end

  defp remote_binding!(integrations, local_name, remote_name) do
    assert {:ok, resolved} =
             IntegrationCatalog.resolve(integrations, "tenant-demo", "records", remote_name)

    %ToolBinding{
      name: local_name,
      type: :mcp,
      conversation_mode: :blocking,
      action: nil,
      remote: resolved
    }
  end

  defp customer_schema do
    %{
      "type" => "object",
      "properties" => %{"customer_id" => %{"type" => "string"}},
      "required" => ["customer_id"],
      "additionalProperties" => false
    }
  end

  defp invoice_schema do
    %{
      "type" => "object",
      "properties" => %{"invoice_number" => %{"type" => "integer"}},
      "required" => ["invoice_number"],
      "additionalProperties" => false
    }
  end

  defp stale_context do
    %Context{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "incarnation-test",
      agent_participant_id: "agent-test",
      source_participant_id: "caller-test",
      connection_id: "connection-test",
      command_id: "command-test",
      correlation_id: "stale-tool-activation",
      agent_request_id: "request-test",
      tool_call_id: "stale-tool-call"
    }
  end

  defp send_text(correlation_id) do
    assert {:ok, command} =
             SendText.new(
               tenant_id: "tenant-test",
               actor_id: "actor-test",
               room_id: "room-test",
               incarnation_id: "incarnation-test",
               participant_id: "caller-test",
               connection_id: "connection-test",
               correlation_id: correlation_id,
               content: "Hello",
               deadline: DateTime.add(DateTime.utc_now(), 5, :second)
             )

    command
  end

  defp monitor_children(children) do
    Map.new(children, fn {role, pid} -> {role, {pid, Process.monitor(pid)}} end)
  end

  defp assert_children_stopped(monitors) do
    Enum.each(monitors, fn {_role, {pid, monitor}} ->
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, 1_000
    end)
  end

  defp unique_activation_id do
    "act-supervised-#{System.unique_integer([:positive])}"
  end
end
