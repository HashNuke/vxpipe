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

    scope =
      Map.merge(scope, %{
        owner: self(),
        player_monitors: %{},
        started_at_ms: System.monotonic_time(:millisecond)
      })

    try do
      receive do
        {:vxpipe_transfer_phase_start, reference} when is_reference(reference) ->
          start_preparation(Map.put(scope, :reference, reference), prepare, monitor)

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

  def handoff(phase, stage, payload) do
    send(phase, {:vxpipe_transfer_handoff, self(), stage, payload})
    :ok
  end

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

  defp start_preparation(%{audience_request: request} = scope, prepare, monitor)
       when not is_nil(request) do
    task =
      RoomTransferSupervisor.handoff(scope.incarnation_id, fn ->
        with {:ok, audience} <-
               Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanMediaHandoff.run(
                 :audience,
                 scope,
                 request
               ),
             {:ok, preparation} <- prepare.(),
             do: {:ok, {audience, preparation}}
      end)

    await_completion(Map.merge(scope, %{worker: task, stage: :destination_preparation}), monitor)
  end

  defp start_preparation(scope, prepare, monitor) do
    case prepare.() do
      {:ok, preparation} ->
        send(scope.authority, {:vxpipe_transfer_prepared, scope.reference, preparation})
        await_completion(scope, monitor)

      {:handoff, stage, payload} ->
        start_handoff(scope, stage, payload, monitor)

      error ->
        error
    end
  end

  defp await_completion(scope, monitor) do
    if remaining_ms(scope.deadline_ms) == 0 do
      {:error, :deadline_elapsed}
    else
      receive do
        {:vxpipe_transfer_progress, worker, progress} ->
          if match?(%Task{pid: ^worker}, Map.get(scope, :worker)) do
            send(scope.authority, {:vxpipe_transfer_progress, scope.reference, progress})
          end

          await_completion(scope, monitor)

        {:vxpipe_transfer_handoff, authority, stage, payload}
        when authority == scope.authority ->
          if Map.get(scope, :worker) do
            {:error, :handoff_already_running}
          else
            start_handoff(scope, stage, payload, monitor)
          end

        {reference, result} when is_reference(reference) ->
          case Map.get(scope, :worker) do
            %Task{ref: ^reference} ->
              Process.demonitor(reference, [:flush])
              worker_result(scope, result, monitor)

            _stale ->
              await_completion(scope, monitor)
          end

        {:vxpipe_wait_playback, _player, _episode, {:failed, _reason}} ->
          {:error, :wait_playback_failed}

        {:vxpipe_wait_playback, player, _episode, status} = message ->
          scope =
            if status in [:stopped, :completed], do: settle_player(scope, player), else: scope

          if worker = Map.get(scope, :worker), do: send(worker.pid, message)
          await_completion(scope, monitor)

        {:DOWN, reference, :process, _player, _reason}
        when is_map_key(scope.player_monitors, reference) ->
          {:error, :wait_playback_failed}

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

  defp start_handoff(scope, stage, payload, monitor) do
    task =
      RoomTransferSupervisor.handoff(scope.incarnation_id, fn ->
        Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanMediaHandoff.run(
          stage,
          scope,
          payload
        )
      end)

    await_completion(Map.merge(scope, %{worker: task, stage: stage}), monitor)
  end

  defp worker_result(
         %{stage: :destination_preparation} = scope,
         {:ok, {audience, preparation}},
         monitor
       ) do
    scope = Map.put(scope, :player_monitors, Map.new(audience.waits, &{Process.monitor(&1), &1}))
    send(scope.authority, {:vxpipe_transfer_prepared, scope.reference, preparation})

    await_completion(
      scope |> Map.drop([:worker, :stage]) |> Map.put(:audience, audience),
      monitor
    )
  end

  defp worker_result(%{stage: :destination_preparation}, error, _monitor), do: error

  defp worker_result(scope, result, monitor) do
    send(scope.authority, {:vxpipe_transfer_handoff_result, scope.reference, scope.stage, result})
    await_completion(Map.drop(scope, [:worker, :stage]), monitor)
  end

  defp settle_player(scope, player) do
    monitors =
      Enum.reduce(scope.player_monitors, scope.player_monitors, fn
        {reference, ^player}, monitors ->
          Process.demonitor(reference, [:flush])
          Map.delete(monitors, reference)

        _other, monitors ->
          monitors
      end)

    %{scope | player_monitors: monitors}
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
