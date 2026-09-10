defmodule Vxpipe.CallEngine.Tool.InvocationSupervisorTest do
  use ExUnit.Case, async: false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.TestSubmittedInlineTool

  alias Vxpipe.CallEngine.Tool.{
    Context,
    InvocationBinding,
    InvocationCompletion,
    InvocationSupervisor
  }

  setup do
    Application.put_env(:vxpipe_call_engine, :submitted_inline_tool_observer, self())

    on_exit(fn ->
      Application.delete_env(:vxpipe_call_engine, :submitted_inline_tool_observer)
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

    assert_receive {:submitted_inline_tool_started, execution, "first"}
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
    send(execution, :release_submitted_inline_tool)

    assert_receive {:vxpipe_tool_invocation_finished, ^worker,
                    %InvocationCompletion{
                      invocation_id: "invocation-one",
                      tool_name: "submitted_inline_tool",
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

    assert_receive {:submitted_inline_tool_started, execution, "slow"}
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

  defp start_invocation_supervisor(maximum_children) do
    activation_id = "act-invocations-#{System.unique_integer([:positive])}"

    start_supervised!(
      {InvocationSupervisor, activation_id: activation_id, maximum_children: maximum_children}
    )
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
end
