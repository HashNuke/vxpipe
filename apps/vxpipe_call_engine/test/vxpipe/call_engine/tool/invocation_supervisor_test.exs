defmodule Vxpipe.CallEngine.Tool.InvocationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.RemoteMCP.{IntegrationOwner, ResolvedTool}
  alias Vxpipe.CallEngine.RemoteMCPFixture

  alias Vxpipe.CallEngine.{
    TestRemoteMCPConnectionProvider,
    TestRemoteMCPProtocolClient,
    TestSubmittedHostTool
  }

  alias Vxpipe.CallEngine.CallVariables.Binding

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationSupervisor
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
    end)
  end

  test "hands a legacy inline host tool to a capacity-bounded supervised worker" do
    supervisor = start_invocation_supervisor(1)
    binding = host_binding(:blocking)
    context = context()

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-one",
               binding: binding,
               arguments: %{"value" => "first"},
               context: context,
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    assert_receive {:submitted_host_tool_started, execution, "first"}
    refute execution == self()

    assert Enum.any?(DynamicSupervisor.which_children(supervisor), fn
             {_id, ^worker, :worker, _modules} -> true
             _child -> false
           end)

    assert {:error, :max_children} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-two",
               binding: binding,
               arguments: %{"value" => "second"},
               context: context,
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    monitor = Process.monitor(worker)
    send(execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-one",
                      tool_name: "submitted_host_tool",
                      conversation_mode: :blocking,
                      context: completed_context,
                      outcome: {:ok, %{"value" => "first"}}
                    }}

    assert completed_context == %{context | tool_call_id: "invocation-one"}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    refute_receive {:vxpipe_tool_invocation_finished, ^worker, _duplicate}
  end

  test "reports an invocation deadline as unknown and stops its execution" do
    supervisor = start_invocation_supervisor(1)

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-timeout",
               binding: host_binding(:non_blocking),
               arguments: %{"value" => "slow"},
               context: context(),
               reply_to: self(),
               timeout_ms: 25,
               maximum_result_bytes: 4_096
             )

    assert_receive {:submitted_host_tool_started, execution, "slow"}
    execution_monitor = Process.monitor(execution)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-timeout",
                      conversation_mode: :non_blocking,
                      outcome: {:error, :unknown}
                    }},
                   500

    assert_receive {:DOWN, ^execution_monitor, :process, ^execution, _reason}
    refute_receive {:vxpipe_tool_invocation_finished, ^worker, _duplicate}
  end

  test "bounds a successful worker result before terminal handoff" do
    supervisor = start_invocation_supervisor(1)

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-large-result",
               binding: host_binding(:blocking),
               arguments: %{"value" => "larger-than-eight-bytes"},
               context: context(),
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 8
             )

    assert_receive {:submitted_host_tool_started, execution, "larger-than-eight-bytes"}
    send(execution, :release_submitted_host_tool)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-large-result",
                      outcome: {:error, :invalid_result}
                    }}

    refute inspect(:sys.get_state(supervisor)) =~ "larger-than-eight-bytes"
  end

  test "maps an abnormal execution exit to one bounded worker failure" do
    supervisor = start_invocation_supervisor(1)

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-worker-failure",
               binding: host_binding(:blocking),
               arguments: %{"value" => "private-failure-input"},
               context: context(),
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    assert_receive {:submitted_host_tool_started, execution, "private-failure-input"}
    Process.exit(execution, :kill)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-worker-failure",
                      outcome: {:error, :tool_failed}
                    }}

    refute_receive {:vxpipe_tool_invocation_finished, ^worker, _duplicate}
  end

  test "keeps a prepared invocation dormant until its owner explicitly begins it" do
    supervisor = start_invocation_supervisor(1)

    assert {:ok, worker} =
             InvocationSupervisor.prepare_invocation(supervisor,
               invocation_id: "invocation-prepared",
               binding: host_binding(:blocking),
               arguments: %{"value" => "prepared"},
               context: context(),
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    refute_receive {:submitted_host_tool_started, _execution, "prepared"}
    assert :ok = InvocationSupervisor.begin_invocation(worker)
    assert_receive {:submitted_host_tool_started, execution, "prepared"}
    send(execution, :release_submitted_host_tool)
  end

  test "hands a Call Variables read to the same supervised worker boundary" do
    owner = self()
    variable_server = start_supervised!({Task, fn -> variable_server_loop(owner) end})
    supervisor = start_invocation_supervisor(1)
    context = context()

    variable_binding = %Binding{
      server: variable_server,
      tenant_id: context.tenant_id,
      room_id: context.room_id,
      incarnation_id: context.incarnation_id,
      participant_id: context.agent_participant_id,
      activation_id: "activation-agent",
      read_sections: ["order"],
      write_sections: []
    }

    assert {:ok, binding} =
             InvocationBinding.from_call_variables("read_variables", variable_binding)

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-variables-read",
               binding: binding,
               arguments: %{"sections" => ["order"]},
               context: context,
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    assert_receive {:test_call_variables_read, execution, ["order"]}
    refute execution == self()

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-variables-read",
                      tool_name: "read_variables",
                      conversation_mode: :blocking,
                      outcome:
                        {:ok,
                         %{
                           "global_revision" => 0,
                           "sections" => %{
                             "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
                           }
                         }}
                    }}
  end

  test "hands a remote MCP call to the same supervised worker boundary" do
    response = {:ok, %{"content" => [%{"type" => "text", "text" => "found"}]}}
    observer = self()

    client =
      start_supervised!(
        {Agent, fn -> %{responses: [{:wait, observer, response}], invocations: []} end}
      )

    generation = "credential-#{System.unique_integer([:positive, :monotonic])}"

    {integrations, %ToolBinding{remote: %ResolvedTool{}} = resolved} =
      RemoteMCPFixture.binding!(client, self(), "private", credential_generation: generation)

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: "activation-remote-worker",
         tools: %{"customer_lookup" => resolved},
         integrations: integrations,
         connection_provider: TestRemoteMCPConnectionProvider,
         protocol: TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}
    assert {:ok, binding} = InvocationBinding.from_remote(resolved, owner)
    supervisor = start_invocation_supervisor(1)

    assert {:ok, worker} =
             InvocationSupervisor.start_invocation(supervisor,
               invocation_id: "invocation-remote",
               binding: binding,
               arguments: %{"customer_id" => "customer-42"},
               context: context(),
               reply_to: self(),
               timeout_ms: 1_000,
               maximum_result_bytes: 4_096
             )

    assert_receive {:test_remote_mcp_invocation_started, execution}
    refute execution == self()
    send(execution, :release_test_remote_mcp)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-remote",
                      tool_name: "customer_lookup",
                      conversation_mode: :blocking,
                      outcome: ^response
                    }}
  end

  defp start_invocation_supervisor(maximum_children) do
    activation_id = "act-invocations-#{System.unique_integer([:positive])}"

    start_supervised!(
      {InvocationSupervisor, activation_id: activation_id, maximum_children: maximum_children}
    )
  end

  defp host_binding(conversation_mode) do
    resolved = %ToolBinding{
      name: "submitted_host_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedHostTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)
    binding
  end

  defp context do
    %Context{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "incarnation-demo",
      agent_participant_id: "participant-agent",
      source_participant_id: "participant-caller",
      connection_id: "connection-caller",
      command_id: "command-demo",
      correlation_id: "turn-demo",
      agent_request_id: "request-demo",
      tool_call_id: nil
    }
  end

  defp variable_server_loop(owner) do
    receive do
      {:"$gen_call", {execution, _tag} = from, {:read, command}} ->
        send(owner, {:test_call_variables_read, execution, command.sections})

        GenServer.reply(
          from,
          {:ok,
           %{
             "global_revision" => 0,
             "sections" => %{
               "order" => %{"revision" => 0, "value" => %{"id" => "order-1"}}
             }
           }}
        )

        variable_server_loop(owner)
    end
  end
end
