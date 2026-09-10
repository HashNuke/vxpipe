defmodule Vxpipe.AgentRuntime.TestExecutor do
  @behaviour Vxpipe.AgentRuntime.Executor

  @impl true
  def submit(binding, arguments, context, invocation_id) do
    send(binding.test_owner, {
      :tool_submitted,
      self(),
      binding.identity,
      arguments,
      context,
      invocation_id
    })

    binding.submission
  end
end
