defmodule Vxpipe.CallEngine.Tool.ConversationAdmission do
  @moduledoc false

  alias Vxpipe.CallEngine.Tool.{InvocationRegistry, InvocationStatus}

  @holding_response "Please hold while I finish the current request."

  @spec decide(GenServer.server()) :: :admit | :hold | {:error, :unavailable}
  def decide(invocation_registry) do
    case InvocationRegistry.snapshot(invocation_registry) do
      {:ok, statuses} ->
        statuses
        |> Enum.map(fn
          %InvocationStatus{conversation_mode: mode} -> mode
          _invalid -> :invalid
        end)
        |> decide_modes()

      _unavailable ->
        {:error, :unavailable}
    end
  end

  @spec holding_response() :: String.t()
  def holding_response, do: @holding_response

  @spec decide_modes([:blocking | :non_blocking]) :: :admit | :hold | {:error, :unavailable}
  def decide_modes(modes) when is_list(modes) do
    Enum.reduce_while(modes, :admit, fn
      :blocking, _decision -> {:halt, :hold}
      :non_blocking, decision -> {:cont, decision}
      _invalid, _decision -> {:halt, {:error, :unavailable}}
    end)
  end
end
