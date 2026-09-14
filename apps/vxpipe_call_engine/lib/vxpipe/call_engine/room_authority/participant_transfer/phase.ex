defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Phase do
  @moduledoc false

  alias Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.Pending
  alias Vxpipe.CallEngine.RoomTransferSupervisor

  @request_timeout_ms 1_000

  @type scope :: %{
          authority: pid(),
          owner: pid(),
          incarnation_id: String.t(),
          attempt_id: String.t(),
          deadline_ms: integer()
        }

  def run(scope, prepare) when is_function(prepare, 0) do
    monitor = Process.monitor(scope.authority)
    scope = Map.put(scope, :owner, self())

    try do
      receive do
        {:vxpipe_transfer_phase_start, reference} when is_reference(reference) ->
          with {:ok, preparation} <- prepare.() do
            send(scope.authority, {:vxpipe_transfer_prepared, reference, preparation})
            await_completion(scope, monitor)
          end

        {:DOWN, ^monitor, :process, _owner, _reason} ->
          {:error, :preparation_process_down}
      after
        remaining_ms(scope.deadline_ms) -> {:error, :deadline_elapsed}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  @spec scope(pid()) :: {:ok, scope()} | {:error, :unavailable}
  def scope(phase), do: request(phase, :scope, @request_timeout_ms)

  @spec complete(pid(), integer()) :: :ok | {:error, :not_owner | :unavailable}
  def complete(phase, deadline_ms) do
    request(phase, :complete, min(@request_timeout_ms, remaining_ms(deadline_ms)))
  end

  @spec finish(Pending.t()) :: :ok | {:error, :not_owner | :unavailable}
  def finish(%Pending{} = pending) do
    result = complete(pending.task.pid, pending.deadline_ms)
    settle(pending)
    result
  end

  @spec cancel(Pending.t()) :: :ok
  def cancel(%Pending{} = pending) do
    settle(pending)
    _ = RoomTransferSupervisor.terminate(pending.request.incarnation_id, pending.task.pid)
    :ok
  end

  defp settle(pending) do
    Process.demonitor(pending.task.ref, [:flush])
    _ = Process.cancel_timer(pending.timer)
    :ok
  end

  defp await_completion(scope, monitor) do
    if remaining_ms(scope.deadline_ms) == 0 do
      {:error, :deadline_elapsed}
    else
      receive do
        {:vxpipe_transfer_phase, _caller, reply, :scope} ->
          send(reply, {reply, {:ok, scope}})
          await_completion(scope, monitor)

        {:vxpipe_transfer_phase, caller, reply, :complete} ->
          complete_request(scope, monitor, caller, reply)

        {:DOWN, ^monitor, :process, _owner, _reason} ->
          {:error, :preparation_process_down}
      after
        remaining_ms(scope.deadline_ms) -> {:error, :deadline_elapsed}
      end
    end
  end

  defp complete_request(scope, monitor, caller, reply) do
    cond do
      remaining_ms(scope.deadline_ms) == 0 ->
        {:error, :deadline_elapsed}

      caller == scope.authority ->
        send(reply, {reply, :ok})
        :phase_finished

      true ->
        send(reply, {reply, {:error, :not_owner}})
        await_completion(scope, monitor)
    end
  end

  defp request(_phase, _action, 0), do: {:error, :unavailable}

  defp request(phase, action, timeout_ms) do
    reference = :erlang.monitor(:process, phase, [{:alias, :reply_demonitor}])

    try do
      send(phase, {:vxpipe_transfer_phase, self(), reference, action})

      receive do
        {^reference, result} -> result
        {:DOWN, ^reference, :process, ^phase, _reason} -> {:error, :unavailable}
      after
        timeout_ms -> {:error, :unavailable}
      end
    after
      Process.demonitor(reference, [:flush])

      receive do
        {^reference, _result} -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp remaining_ms(deadline_ms), do: max(deadline_ms - System.monotonic_time(:millisecond), 0)
end
