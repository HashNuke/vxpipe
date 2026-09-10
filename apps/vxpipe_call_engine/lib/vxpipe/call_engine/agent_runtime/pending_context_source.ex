defmodule Vxpipe.CallEngine.AgentRuntime.PendingContextSource do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.PendingContextSource

  alias Vxpipe.AgentRuntime.PendingInvocation
  alias Vxpipe.CallEngine.AgentRuntime.Correlation
  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationStatus}

  @impl true
  def snapshot(registry, %Correlation{} = correlation, timeout_ms)
      when is_integer(timeout_ms) and timeout_ms > 0 do
    if Correlation.registry?(correlation, registry) do
      with {:ok, statuses} <- InvocationRegistry.snapshot(registry, timeout_ms) do
        pending_invocations(statuses)
      end
    else
      {:error, :unavailable}
    end
  end

  def snapshot(_registry, _correlation, _timeout_ms), do: {:error, :unavailable}

  defp pending_invocations(statuses) do
    Enum.reduce_while(statuses, {:ok, []}, fn status, {:ok, pending} ->
      case pending_invocation(status) do
        {:ok, invocation} -> {:cont, {:ok, [invocation | pending]}}
        {:error, _reason} -> {:halt, {:error, :invalid_pending_state}}
      end
    end)
    |> case do
      {:ok, pending} -> {:ok, Enum.reverse(pending)}
      {:error, _reason} = error -> error
    end
  end

  defp pending_invocation(%InvocationStatus{} = status) do
    PendingInvocation.new(
      invocation_id: status.invocation_id,
      tool_name: status.tool_name,
      conversation_mode: status.conversation_mode,
      source_turn_id: status.source_turn_id,
      status: status.status
    )
  end

  defp pending_invocation(_status), do: {:error, :invalid_status}
end
