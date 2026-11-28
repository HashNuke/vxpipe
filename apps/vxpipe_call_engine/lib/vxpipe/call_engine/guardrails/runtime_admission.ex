defmodule Vxpipe.CallEngine.Guardrails.RuntimeAdmission do
  @moduledoc false

  @behaviour Vxpipe.AgentRuntime.RoundAdmission

  alias Vxpipe.AgentRuntime.RoundCandidate
  alias Vxpipe.CallEngine.Guardrails.TransferAdmission
  alias Vxpipe.CallEngine.RoomAuthority

  @impl true
  def admit(%RoundCandidate{} = candidate, context, state)
      when is_map(context) and is_map(state) do
    case TransferAdmission.joint_admit(candidate, context, state) do
      {:accept, %{binds: binds}} -> bind_verdicts(state, binds)
      {:repair, _repair} = repair -> repair
      {:failure, _reason} = failure -> failure
    end
  end

  def admit(_candidate, _context, _state), do: {:failure, :error}

  # Binds are recorded room-side before acceptance so the terminal execution
  # consumes each verdict exactly once. A bind failure (room gone) fails the
  # round; the worker execution gate re-checks rather than bypassing.
  defp bind_verdicts(_state, []), do: {:accept, %{binds: []}}

  defp bind_verdicts(%{room_authority: room}, binds) when is_list(binds) do
    Enum.reduce_while(binds, {:accept, %{binds: binds}}, fn entry, accepted ->
      case RoomAuthority.bind_transfer_verdict(room, entry) do
        :ok -> {:cont, accepted}
        {:error, _reason} -> {:halt, {:failure, :error}}
      end
    end)
  end

  defp bind_verdicts(_state, _binds), do: {:failure, :error}
end
