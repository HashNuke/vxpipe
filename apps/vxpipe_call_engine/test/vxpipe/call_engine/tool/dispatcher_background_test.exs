defmodule Vxpipe.CallEngine.Tool.DispatcherBackgroundTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.RemoteMCP.IntegrationOwner
  alias Vxpipe.CallEngine.RemoteMCPFixture
  alias Vxpipe.CallEngine.TestBlockingTool
  alias Vxpipe.CallEngine.Tool.{BackgroundSupervisor, Context, Dispatcher}

  @admission_event [:vxpipe, :call_engine, :background_tool, :admission]
  @stop_event [:vxpipe, :call_engine, :background_tool, :stop]

  setup do
    Application.put_env(:vxpipe_call_engine, :blocking_tool_observer, self())
    on_exit(fn -> Application.delete_env(:vxpipe_call_engine, :blocking_tool_observer) end)

    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        [@admission_event, @stop_event],
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "accepts one bounded invocation without waiting and reports its result once" do
    activation_id = "act-background-#{System.unique_integer([:positive])}"

    supervisor =
      start_supervised!({BackgroundSupervisor, activation_id: activation_id, maximum_children: 1})

    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: activation_id,
         tools: [TestBlockingTool],
         maximum_result_bytes: 4_096,
         maximum_background_tools: 1,
         background_tool_timeout_ms: 1_000,
         background_supervisor: supervisor,
         completion_target: self()}
      )

    first = context("request-one", "command-one")
    second = context("request-two", "command-two")

    assert :ok =
             Dispatcher.register_tool_call(dispatcher, first.agent_request_id, %{
               tool_call_id: "tool-one",
               tool_name: "wait_for_test",
               arguments: %{}
             })

    assert {:ok, %{"invocation_id" => "tool-one", "status" => "running"}} =
             Dispatcher.submit(dispatcher, "wait_for_test", %{}, first)

    assert_receive {:background_tool_telemetry, @admission_event,
                    %{count: 1, reserved: 1, limit: 1}, %{outcome: :accepted}}

    assert_receive {:test_blocking_tool_started, worker}

    assert :ok =
             Dispatcher.register_tool_call(dispatcher, second.agent_request_id, %{
               tool_call_id: "tool-two",
               tool_name: "wait_for_test",
               arguments: %{}
             })

    assert {:error, :queue_full} = Dispatcher.submit(dispatcher, "wait_for_test", %{}, second)

    assert_receive {:background_tool_telemetry, @admission_event,
                    %{count: 1, reserved: 1, limit: 1}, %{outcome: :saturated}}

    send(worker, :release_test_tool)

    assert_receive {:vxpipe_background_tool_finished, ^dispatcher, invocation}, 1_000
    assert invocation.call.id == "tool-one"
    assert invocation.call.name == "wait_for_test"
    assert invocation.context == %{first | tool_call_id: "tool-one"}
    assert invocation.outcome == {:ok, %{"released" => true}}

    assert_receive {:background_tool_telemetry, @stop_event, %{count: 1, duration: duration},
                    %{outcome: :ok}}

    assert is_integer(duration) and duration >= 0
    refute_receive {:vxpipe_background_tool_finished, ^dispatcher, _duplicate}

    assert :ok = Dispatcher.acknowledge_background_completion(dispatcher, "tool-one")

    assert {:ok, %{"invocation_id" => "tool-two", "status" => "running"}} =
             Dispatcher.submit(dispatcher, "wait_for_test", %{}, second)
  end

  test "runs a pinned remote MCP tool in the bounded background lifecycle" do
    activation_id = "act-remote-background-#{System.unique_integer([:positive])}"
    result = %{"content" => [%{"type" => "text", "text" => "found"}]}
    observer = self()

    client =
      start_supervised!(
        {Agent,
         fn ->
           %{
             responses: [{:wait, observer, {:ok, result}}],
             invocations: []
           }
         end}
      )

    {integrations, binding} = RemoteMCPFixture.binding!(client, self(), "private")

    owner =
      start_supervised!(
        {IntegrationOwner,
         activation_id: activation_id,
         tools: %{"customer_lookup" => binding},
         integrations: integrations,
         connection_provider: Vxpipe.CallEngine.TestRemoteMCPConnectionProvider,
         protocol: Vxpipe.CallEngine.TestRemoteMCPProtocolClient}
      )

    assert_receive {:test_remote_mcp_opened, _key, _config}

    supervisor =
      start_supervised!({BackgroundSupervisor, activation_id: activation_id, maximum_children: 1})

    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: activation_id,
         tools: [],
         remote_mcp: owner,
         remote_tools: ["customer_lookup"],
         maximum_result_bytes: 4_096,
         maximum_background_tools: 1,
         background_tool_timeout_ms: 1_000,
         background_supervisor: supervisor,
         completion_target: self()}
      )

    call_context = context("request-remote", "command-remote")

    assert :ok =
             Dispatcher.register_tool_call(dispatcher, call_context.agent_request_id, %{
               tool_call_id: "tool-remote",
               tool_name: "customer_lookup",
               arguments: %{"customer_id" => "customer-42"}
             })

    assert {:ok, %{"invocation_id" => "tool-remote", "status" => "running"}} =
             Dispatcher.submit(
               dispatcher,
               "customer_lookup",
               %{"customer_id" => "customer-42"},
               call_context
             )

    assert_receive {:test_remote_mcp_invocation_started, worker}
    assert {:ok, nil} = Dispatcher.variable_projection(dispatcher)
    send(worker, :release_test_remote_mcp)

    assert_receive {:vxpipe_background_tool_finished, ^dispatcher, invocation}, 1_000
    assert invocation.call.id == "tool-remote"
    assert invocation.call.name == "customer_lookup"
    assert invocation.outcome == {:ok, result}

    assert [remote_invocation] = Agent.get(client, & &1.invocations)
    assert remote_invocation.name == "lookup_customer"
    assert remote_invocation.arguments == %{"customer_id" => "customer-42"}
  end

  test "reports an accepted timeout as unknown without resubmitting it" do
    {dispatcher, _supervisor} = start_background_runtime(timeout_ms: 25)
    context = context("request-timeout", "command-timeout")

    register(dispatcher, context, "tool-timeout")

    assert {:ok, %{"invocation_id" => "tool-timeout", "status" => "running"}} =
             Dispatcher.submit(dispatcher, "wait_for_test", %{}, context)

    assert_receive {:test_blocking_tool_started, _worker}

    assert_receive {:vxpipe_background_tool_finished, ^dispatcher, invocation}, 500
    assert invocation.call.id == "tool-timeout"
    assert invocation.outcome == {:error, :unknown}

    assert_receive {:background_tool_telemetry, @stop_event, %{count: 1, duration: duration},
                    %{outcome: :unknown}}

    assert is_integer(duration) and duration >= 0
    refute_receive {:test_blocking_tool_started, _duplicate}
    refute_receive {:vxpipe_background_tool_finished, ^dispatcher, _duplicate}
  end

  test "does not acknowledge work when its supervised worker cannot start" do
    {dispatcher, _supervisor} = start_background_runtime(supervisor_capacity: 0)
    context = context("request-rejected", "command-rejected")

    register(dispatcher, context, "tool-rejected")

    assert {:error, :tool_failed} =
             Dispatcher.submit(dispatcher, "wait_for_test", %{}, context)

    assert_receive {:background_tool_telemetry, @admission_event,
                    %{count: 1, reserved: 0, limit: 1}, %{outcome: :start_failed}}

    refute_receive {:test_blocking_tool_started, _worker}
    refute_receive {:vxpipe_background_tool_finished, ^dispatcher, _completion}
  end

  test "reports local worker termination when its owning subtree stops" do
    {dispatcher, supervisor} = start_background_runtime([])
    context = context("request-terminated", "command-terminated")

    register(dispatcher, context, "tool-terminated")

    assert {:ok, %{"status" => "running"}} =
             Dispatcher.submit(dispatcher, "wait_for_test", %{}, context)

    assert_receive {:test_blocking_tool_started, tool_task}
    monitor = Process.monitor(tool_task)

    :ok = Supervisor.stop(supervisor)
    assert_receive {:DOWN, ^monitor, :process, ^tool_task, _reason}

    assert_receive {:background_tool_telemetry, @stop_event, %{count: 1, duration: duration},
                    %{outcome: :terminated}}

    assert is_integer(duration) and duration >= 0
    refute_receive {:vxpipe_background_tool_finished, ^dispatcher, _completion}
  end

  defp start_background_runtime(options) do
    activation_id = "act-background-#{System.unique_integer([:positive])}"

    supervisor =
      start_supervised!(
        {BackgroundSupervisor,
         activation_id: activation_id,
         maximum_children: Keyword.get(options, :supervisor_capacity, 1)}
      )

    dispatcher =
      start_supervised!(
        {Dispatcher,
         activation_id: activation_id,
         tools: [TestBlockingTool],
         maximum_result_bytes: 4_096,
         maximum_background_tools: 1,
         background_tool_timeout_ms: Keyword.get(options, :timeout_ms, 1_000),
         background_supervisor: supervisor,
         completion_target: self()}
      )

    {dispatcher, supervisor}
  end

  defp register(dispatcher, context, tool_call_id) do
    assert :ok =
             Dispatcher.register_tool_call(dispatcher, context.agent_request_id, %{
               tool_call_id: tool_call_id,
               tool_name: "wait_for_test",
               arguments: %{}
             })
  end

  defp context(request_id, command_id) do
    %Context{
      tenant_id: "tenant-test",
      room_id: "room-test",
      incarnation_id: "rinc-test",
      agent_participant_id: "agent-test",
      source_participant_id: "participant-test",
      connection_id: "connection-test",
      command_id: command_id,
      correlation_id: "correlation-test",
      agent_request_id: request_id,
      tool_call_id: nil
    }
  end

  def handle_telemetry_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:background_tool_telemetry, event, measurements, metadata})
  end
end
