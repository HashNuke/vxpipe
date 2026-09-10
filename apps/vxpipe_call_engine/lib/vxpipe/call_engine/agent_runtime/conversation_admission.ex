defmodule Vxpipe.CallEngine.AgentRuntime.ConversationAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationStatus}

  @holding_response "Please hold while I finish the current request."

  @spec decide(GenServer.server()) :: :admit | :hold | {:error, :unavailable}
  def decide(invocation_registry) do
    with {:ok, statuses} <- InvocationRegistry.snapshot(invocation_registry),
         {:ok, decision} <- decision(statuses) do
      decision
    else
      _unavailable_or_invalid -> {:error, :unavailable}
    end
  end

  @spec holding_response() :: String.t()
  def holding_response, do: @holding_response

  defp decision(statuses) when is_list(statuses) do
    Enum.reduce_while(statuses, {:ok, :admit}, fn
      %InvocationStatus{conversation_mode: :blocking}, _decision ->
        {:halt, {:ok, :hold}}

      %InvocationStatus{conversation_mode: :non_blocking}, decision ->
        {:cont, decision}

      _invalid, _decision ->
        {:halt, {:error, :invalid_status}}
    end)
  end

  defp decision(_statuses), do: {:error, :invalid_statuses}
end
