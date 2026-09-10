defmodule Vxpipe.CallEngine.Tool.InvocationLifecycle do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{
    Call,
    InvocationCompletion,
    InvocationRecord,
    InvocationSubmission,
    PlatformResult
  }

  @spec accepted(pid() | nil, pid(), InvocationSubmission.t()) :: :ok
  def accepted(nil, _capability, %InvocationSubmission{}), do: :ok

  def accepted(target, capability, %InvocationSubmission{} = submission)
      when is_pid(target) and is_pid(capability) do
    call = call(submission)

    send(
      target,
      {:vxpipe_capability_tool_started, capability, submission.context, call}
    )

    :ok
  end

  @spec settled(pid() | nil, pid(), InvocationRecord.t()) :: :ok
  def settled(nil, _capability, %InvocationRecord{}), do: :ok

  def settled(
        target,
        capability,
        %InvocationRecord{
          submission: %InvocationSubmission{} = submission,
          completion: %InvocationCompletion{} = completion
        }
      )
      when is_pid(target) and is_pid(capability) do
    call = call(submission)

    case completion.outcome do
      {:ok, %PlatformResult{effect: effect, result: result}} ->
        send(
          target,
          {:vxpipe_capability_tool_completed, capability, completion.context, call, result}
        )

        send(
          target,
          {:vxpipe_platform_effect, capability, completion.context, effect}
        )

      {:ok, result} ->
        send(
          target,
          {:vxpipe_capability_tool_completed, capability, completion.context, call, result}
        )

      {:error, reason} ->
        send(
          target,
          {:vxpipe_capability_tool_failed, capability, completion.context, call, reason}
        )
    end

    :ok
  end

  defp call(%InvocationSubmission{} = submission) do
    %Call{
      id: submission.invocation_id,
      name: submission.tool_name,
      arguments: submission.arguments
    }
  end
end
