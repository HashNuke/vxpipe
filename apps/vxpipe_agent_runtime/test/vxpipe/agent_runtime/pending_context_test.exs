defmodule Vxpipe.AgentRuntime.PendingContextTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{PendingContext, PendingInvocation}

  test "accepts a bounded unique payload-free projection" do
    invocation = pending_invocation("tool_call_1")

    assert {:ok, [^invocation]} =
             PendingContext.fetch(
               {Vxpipe.AgentRuntime.TestPendingContextSource,
                %{owner: self(), result: {:ok, [invocation]}}},
               %{request_id: "req_1"},
               timeout_ms: 200,
               maximum_invocations: 1
             )

    assert_receive {:pending_context_requested, source_pid, %{request_id: "req_1"}, 200}
    refute source_pid == self()
  end

  test "rejects excessive, duplicate, or payload-bearing source responses" do
    invocation = pending_invocation("tool_call_1")

    assert {:error, :pending_context_too_large} =
             fetch([invocation, pending_invocation("tool_call_2")], maximum_invocations: 1)

    assert {:error, :invalid_pending_context} = fetch([invocation, invocation])

    assert {:error, :invalid_pending_context} =
             fetch([
               %{
                 invocation_id: "tool_call_1",
                 tool_name: "check_balance",
                 arguments: %{"account" => "private"}
               }
             ])
  end

  test "enforces the source timeout and terminates the stalled source call" do
    test_owner = self()

    fetch_task =
      Task.async(fn ->
        PendingContext.fetch(
          {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: test_owner, result: :block}},
          %{},
          timeout_ms: 10
        )
      end)

    assert_receive {:pending_context_requested, source_pid, %{}, 10}
    source_monitor = Process.monitor(source_pid)

    assert {:ok, {:error, :pending_context_unavailable}} = Task.yield(fetch_task, 200)
    assert_receive {:DOWN, ^source_monitor, :process, ^source_pid, _reason}
  end

  defp fetch(result, options \\ []) do
    PendingContext.fetch(
      {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, result}}},
      %{},
      options
    )
  end

  defp pending_invocation(invocation_id) do
    {:ok, invocation} =
      PendingInvocation.new(
        invocation_id: invocation_id,
        tool_name: "check_balance",
        status: :running,
        conversation_mode: :blocking,
        source_turn_id: "turn_1"
      )

    invocation
  end
end
