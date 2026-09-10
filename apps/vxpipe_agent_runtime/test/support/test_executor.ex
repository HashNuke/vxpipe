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

    case binding.submission do
      {:await_release, submission} -> await_release(submission)
      submission -> submission
    end
  end

  defp await_release(submission) do
    receive do
      :release_submission -> submission
    end
  end
end
