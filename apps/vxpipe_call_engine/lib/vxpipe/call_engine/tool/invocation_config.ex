defmodule Vxpipe.CallEngine.Tool.InvocationConfig do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding
  alias Vxpipe.CallEngine.Tool.{Idle, InvocationBinding, InvocationSubmission}
  alias Vxpipe.CallEngine.Tool.Idle.Request

  @keys [
    :tool_invocation_timeout_ms,
    :maximum_tool_invocations,
    :maximum_completed_requests,
    :maximum_tool_result_bytes
  ]

  def defaults do
    :vxpipe_call_engine
    |> Application.fetch_env!(Vxpipe.CallEngine.Application)
    |> Keyword.fetch!(:agent_runtime)
    |> Keyword.take(@keys)
  end

  def for_participant(plan, participant, settings) do
    configured = Keyword.fetch!(settings, :tool_invocation_timeout_ms)

    transfer? =
      Enum.any?(participant.tools, fn
        {_name, %ToolBinding{type: :participant_transfer}} -> true
        _binding -> false
      end)

    timeout =
      if transfer?,
        do: max(configured, plan.transfer_policy.attempt_timeout_ms + 1_000),
        else: configured

    settings
    |> Keyword.take(@keys)
    |> Keyword.put(:tool_invocation_timeout_ms, timeout)
  end

  @spec for_invocation(InvocationSubmission.t(), pos_integer()) :: pos_integer()
  def for_invocation(
        %InvocationSubmission{binding: %InvocationBinding{handler: {:platform, Idle}}} =
          submission,
        configured_timeout_ms
      ) do
    case Request.new(submission.arguments, submission.context) do
      {:ok, request} -> max(configured_timeout_ms, Request.execution_timeout_ms(request))
      {:error, :invalid_arguments} -> configured_timeout_ms
    end
  end

  def for_invocation(
        %InvocationSubmission{
          binding: %InvocationBinding{handler: handler},
          arguments: %{"announcement" => _}
        },
        configured_timeout_ms
      )
      when handler == {:platform, Vxpipe.CallEngine.Tool.Hangup} or
             elem(handler, 0) == :participant_transfer,
      do: configured_timeout_ms + Vxpipe.CallEngine.Tool.Announcement.budget_ms()

  def for_invocation(%InvocationSubmission{}, configured_timeout_ms), do: configured_timeout_ms
end
