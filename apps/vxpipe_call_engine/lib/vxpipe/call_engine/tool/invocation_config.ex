defmodule Vxpipe.CallEngine.Tool.InvocationConfig do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan.ToolBinding

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
end
