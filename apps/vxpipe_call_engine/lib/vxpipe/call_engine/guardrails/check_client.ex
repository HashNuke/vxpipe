defmodule Vxpipe.CallEngine.Guardrails.CheckClient do
  @moduledoc false

  @type verdict ::
          :passed
          | {:blocked, [String.t()]}
          | {:blocked, [String.t()], (-> term())}
          | {:error, atom()}

  @spec check(GenServer.server(), atom(), String.t(), map(), integer()) :: verdict()
  def check(server, event, proposal_id, evidence, deadline_ms)
      when is_atom(event) and is_binary(proposal_id) and is_map(evidence) and
             is_integer(deadline_ms) do
    remaining_ms = deadline_ms - System.monotonic_time(:millisecond)

    if remaining_ms <= 0 do
      {:error, :timeout}
    else
      try do
        GenServer.call(server, {:check, event, proposal_id, evidence, deadline_ms}, remaining_ms)
        |> validate_reply()
      catch
        :exit, {:timeout, _reason} -> {:error, :timeout}
        :exit, _reason -> {:error, :cancelled}
      end
    end
  end

  def check_with_receipt(server, event, proposal, evidence, deadline) do
    check(server, event, proposal, Map.put(evidence, :return_feedback_receipt, true), deadline)
  end

  defp validate_reply({:blocked, lines, callback}) when is_function(callback, 0) do
    case validate_reply({:blocked, lines}) do
      {:blocked, ^lines} -> {:blocked, lines, callback}
      invalid -> invalid
    end
  end

  defp validate_reply(:passed), do: :passed

  defp validate_reply({:blocked, lines}) do
    if is_list(lines) and lines != [] and Enum.all?(lines, &(is_binary(&1) and &1 != "")) do
      {:blocked, lines}
    else
      {:error, :invalid_result}
    end
  end

  defp validate_reply({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp validate_reply(_invalid), do: {:error, :invalid_result}
end
