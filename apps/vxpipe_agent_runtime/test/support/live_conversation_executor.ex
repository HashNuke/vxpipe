defmodule Vxpipe.AgentRuntime.LiveConversationExecutor do
  @moduledoc false
  @behaviour Vxpipe.AgentRuntime.Executor
  alias Vxpipe.AgentRuntime.PendingInvocation

  @impl true
  def submit(binding, arguments, context, invocation_id) do
    {:ok, record} =
      PendingInvocation.new(
        invocation_id: invocation_id,
        tool_name: Atom.to_string(binding.identity),
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: context.request_id
      )

    Agent.update(binding.pending, &[record | &1])

    send(
      binding.test_owner,
      {:tool_submitted, self(), binding.identity, arguments, context, invocation_id}
    )

    {:accepted, :non_blocking}
  end
end
