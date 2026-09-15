defmodule Vxpipe.CallEngine.MediaPolicy.Barrier do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.{Enforcer, Snapshot}

  @spec apply(
          %{optional(pid()) => %{monitor: reference(), connection: pid() | nil}},
          Snapshot.t(),
          pos_integer()
        ) ::
          :ok | {:error, :enforcement_failed}
  def apply(enforcers, %Snapshot{} = snapshot, timeout_ms)
      when is_map(enforcers) and is_integer(timeout_ms) and timeout_ms > 0 do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    Enum.reduce_while(enforcers, :ok, fn {enforcer, registration}, :ok ->
      case apply_enforcer(enforcer, registration.connection, snapshot, deadline) do
        :ok -> {:cont, :ok}
        {:error, _reason} -> {:halt, {:error, :enforcement_failed}}
      end
    end)
  end

  defp apply_enforcer(enforcer, connection, snapshot, deadline) do
    if departed?(connection) do
      :ok
    else
      case Enforcer.apply(enforcer, snapshot, remaining_timeout(deadline)) do
        :ok -> :ok
        error -> if departed?(connection), do: :ok, else: error
      end
    end
  end

  defp departed?(nil), do: false
  defp departed?(connection), do: not Process.alive?(connection)

  defp remaining_timeout(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 1)
  end
end
