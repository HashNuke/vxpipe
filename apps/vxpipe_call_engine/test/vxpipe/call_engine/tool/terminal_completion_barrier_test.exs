defmodule Vxpipe.CallEngine.Tool.TerminalCompletionBarrierTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedHostTool

  alias Vxpipe.CallEngine.Tool.{
    Context,
    ConversationAdmission,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor,
    TerminalCompletionBarrier
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_host_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_host_tool_observer)
    end)
  end

  test "blocking ordinary must finish before barrier releases terminal" do
    {registry, _sup} = start_registry(maximum_invocations: 4)
    ctx = context("turn-barrier-blocking")

    assert {:accepted, :blocking} =
             InvocationRegistry.submit(
               registry,
               host_binding(:blocking),
               %{"value" => "ordinary-blocking"},
               ctx,
               "ordinary-blocking"
             )

    assert_receive {:submitted_host_tool_started, ordinary_worker, "ordinary-blocking"}

    # Barrier waits in background; terminal must not proceed until ordinary finishes.
    barrier =
      Task.async(fn ->
        TerminalCompletionBarrier.await_ordinary(registry, ["ordinary-blocking"],
          timeout_ms: 2_000
        )
      end)

    refute Task.yield(barrier, 100)
    # Still running, not finished.
    assert {:ok, :running} = InvocationRegistry.peek_completion(registry, "ordinary-blocking")

    send(ordinary_worker, :release_submitted_host_tool)
    assert_receive {:vxpipe_tool_completion_available, ^registry, "ordinary-blocking"}

    assert :ok = Task.await(barrier, 2_000)

    assert {:ok, {:ok, %{"value" => "ordinary-blocking"}}} =
             InvocationRegistry.peek_completion(registry, "ordinary-blocking")
  end

  test "nonblocking ordinary must finish, caller-turn admission stays open while it runs" do
    {registry, _sup} = start_registry(maximum_invocations: 4)
    ctx = context("turn-barrier-nonblocking")

    assert {:accepted, :non_blocking} =
             InvocationRegistry.submit(
               registry,
               host_binding(:non_blocking),
               %{"value" => "ordinary-nonblocking"},
               ctx,
               "ordinary-nonblocking"
             )

    assert_receive {:submitted_host_tool_started, ordinary_worker, "ordinary-nonblocking"}

    # Nonblocking does not hold caller turns.
    assert :admit = ConversationAdmission.decide(registry)

    barrier =
      Task.async(fn ->
        TerminalCompletionBarrier.await_ordinary(registry, ["ordinary-nonblocking"],
          timeout_ms: 2_000
        )
      end)

    refute Task.yield(barrier, 100)

    # Admission still open while nonblocking runs (preserve caller-turn admission).
    assert :admit = ConversationAdmission.decide(registry)

    send(ordinary_worker, :release_submitted_host_tool)
    assert_receive {:vxpipe_tool_completion_available, ^registry, "ordinary-nonblocking"}

    assert :ok = Task.await(barrier, 2_000)
  end

  test "ordinary failure withholds terminal effect with correlated reason" do
    {registry, _sup} = start_registry(maximum_invocations: 4)
    ctx = context("turn-barrier-failed")

    # Invalid args fail immediately without release control.
    assert {:accepted, :blocking} =
             InvocationRegistry.submit(
               registry,
               host_binding(:blocking),
               %{"unexpected" => "args"},
               ctx,
               "ordinary-failed"
             )

    assert_receive {:vxpipe_tool_completion_available, ^registry, "ordinary-failed"}

    assert {:ok, {:error, :tool_failed}} =
             InvocationRegistry.peek_completion(registry, "ordinary-failed")

    assert {:error, :ordinary_failed} =
             TerminalCompletionBarrier.await_ordinary(registry, ["ordinary-failed"],
               timeout_ms: 500
             )

    # Completion ownership may acknowledge the error before the terminal worker observes it.
    assert {:ok, lease} = InvocationRegistry.lease_next(registry, "continuation")
    :ok = InvocationRegistry.acknowledge_completion(registry, "ordinary-failed", lease.lease_id)

    assert {:error, :ordinary_failed} =
             TerminalCompletionBarrier.await_ordinary(registry, ["ordinary-failed"])
  end

  test "stale registry cancels barrier without deadlock" do
    {registry, _sup} = start_registry(maximum_invocations: 2)
    ctx = context("turn-barrier-stale")

    assert {:accepted, :blocking} =
             InvocationRegistry.submit(
               registry,
               host_binding(:blocking),
               %{"value" => "ordinary-stale"},
               ctx,
               "ordinary-stale"
             )

    assert_receive {:submitted_host_tool_started, ordinary_worker, "ordinary-stale"}

    # Stop registry to simulate stale activation; barrier must abort under bound.
    :ok = GenServer.stop(registry, :normal)

    assert {:error, reason} =
             TerminalCompletionBarrier.await_ordinary(registry, ["ordinary-stale"],
               timeout_ms: 500
             )

    assert reason in [:stale, :timeout, :unavailable]

    send(ordinary_worker, :release_submitted_host_tool)
  end

  defp start_registry(options) do
    activation_id = "act-terminal-barrier-#{System.unique_integer([:positive])}"
    maximum_invocations = Keyword.fetch!(options, :maximum_invocations)

    supervisor =
      start_supervised!(
        {InvocationSupervisor,
         activation_id: activation_id, maximum_children: maximum_invocations}
      )

    registry =
      start_supervised!(
        {InvocationRegistry,
         activation_id: activation_id,
         participant_id: "agent-test",
         invocation_supervisor: supervisor,
         completion_target: self(),
         maximum_invocations: maximum_invocations,
         maximum_consumed_invocations: 8,
         invocation_timeout_ms: 1_000,
         maximum_result_bytes: 4_096}
      )

    {registry, supervisor}
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

  defp context(correlation_id) do
    %Context{
      tenant_id: "tenant-demo",
      room_id: "room-demo",
      incarnation_id: "incarnation-demo",
      agent_participant_id: "participant-agent",
      source_participant_id: "participant-caller",
      connection_id: "connection-caller",
      command_id: "command-#{correlation_id}",
      correlation_id: correlation_id,
      agent_request_id: "request-#{correlation_id}",
      tool_call_id: nil
    }
  end
end
