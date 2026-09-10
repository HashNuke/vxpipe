defmodule Vxpipe.CallEngine.AgentRuntime.InvocationAdaptersTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{Executor, PendingContext, PendingInvocation}
  alias Vxpipe.CallEngine.AgentRuntime.{Correlation, InvocationExecutor, PendingContextSource}
  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedInlineTool

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationRegistry,
    InvocationSupervisor
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_inline_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_inline_tool_observer)
    end)
  end

  test "submits through the registry and projects its payload-free pending state" do
    {registry, _supervisor} = start_registry()
    correlation = Correlation.new(registry, tool_context())
    binding = host_binding(:non_blocking)

    assert {:accepted, :non_blocking} =
             Executor.submit(
               InvocationExecutor,
               binding,
               %{"value" => "private-result"},
               correlation,
               "invocation-one"
             )

    assert_receive {:submitted_inline_tool_started, execution, "private-result"}

    assert {:ok,
            [
              %PendingInvocation{
                invocation_id: "invocation-one",
                tool_name: "submitted_inline_tool",
                conversation_mode: :non_blocking,
                source_turn_id: "turn-demo",
                status: :running
              }
            ]} =
             PendingContext.fetch(
               {PendingContextSource, registry},
               correlation,
               timeout_ms: 500,
               maximum_invocations: 4
             )

    send(execution, :release_submitted_inline_tool)
    assert_receive {:vxpipe_tool_completion_available, ^registry, "invocation-one"}

    assert {:ok, [%PendingInvocation{status: :terminal_queued}]} =
             PendingContext.fetch(
               {PendingContextSource, registry},
               correlation,
               timeout_ms: 500,
               maximum_invocations: 4
             )

    refute inspect(correlation) =~ "private-result"
  end

  defp start_registry do
    activation_id = "act-adapters-#{System.unique_integer([:positive])}"

    supervisor =
      start_supervised!({InvocationSupervisor, activation_id: activation_id, maximum_children: 2})

    registry =
      start_supervised!(
        {InvocationRegistry,
         activation_id: activation_id,
         invocation_supervisor: supervisor,
         completion_target: self(),
         maximum_invocations: 2,
         maximum_consumed_invocations: 4,
         invocation_timeout_ms: 1_000,
         maximum_result_bytes: 4_096}
      )

    {registry, supervisor}
  end

  defp host_binding(conversation_mode) do
    resolved = %ToolBinding{
      name: "submitted_inline_tool",
      type: :host,
      conversation_mode: conversation_mode,
      action: TestSubmittedInlineTool,
      remote: nil
    }

    assert {:ok, binding} = InvocationBinding.from_resolved(resolved)
    binding
  end

  defp tool_context do
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
end
