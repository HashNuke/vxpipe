defmodule Vxpipe.MCP.SessionOperation do
  @moduledoc false

  alias Vxpipe.MCP.SessionLifecycle

  @failure {:error, :connection_failed}

  # Only this opener's authorization/readiness worker is cancelled. The existing
  # integration and its other operations remain owned by the host.
  def run(integration, deadline, callback, opts \\ []) do
    with {:ok, operation} <-
           SessionLifecycle.prepare_operation(
             integration,
             deadline,
             Keyword.get(opts, :watch, [])
           ) do
      try do
        execute(
          integration,
          operation,
          deadline,
          callback,
          Keyword.get(opts, :publish_ready?, true)
        )
      after
        SessionLifecycle.cancel_operation(integration, operation)
      end
    end
  catch
    :exit, _reason -> @failure
  end

  defp execute(integration, operation, deadline, callback, publish_ready?) do
    caller = self()

    transport =
      {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:transport_workers, integration}}}

    child =
      Supervisor.child_spec(
        {Task, fn -> worker(integration, operation, caller, deadline) end},
        restart: :temporary,
        shutdown: :brutal_kill
      )

    admission = Task.async(fn -> start_child(transport, child) end)

    case Task.yield(admission, remaining(deadline)) || Task.shutdown(admission, :brutal_kill) do
      {:ok, {:ok, worker}} ->
        await_worker(integration, operation, worker, deadline, callback, publish_ready?)

      _failed ->
        @failure
    end
  end

  defp start_child(transport, child) do
    DynamicSupervisor.start_child(transport, child)
  catch
    :exit, _reason -> @failure
  end

  defp worker(integration, operation, caller, deadline) do
    caller_ref = Process.monitor(caller)

    with :ok <- SessionLifecycle.claim_operation(integration, operation, deadline) do
      receive do
        {^operation, callback} ->
          result = invoke(callback)
          send(caller, {operation, result})

        {:DOWN, ^caller_ref, :process, ^caller, _reason} ->
          :ok
      after
        remaining(deadline) -> :ok
      end
    end
  catch
    :exit, _reason -> :ok
  end

  defp invoke(callback) do
    callback.()
  rescue
    _exception -> @failure
  catch
    _kind, _reason -> @failure
  end

  defp await_worker(integration, operation, worker, deadline, callback, publish_ready?) do
    monitor = Process.monitor(worker)
    send(worker, {operation, callback})

    result =
      receive do
        {^operation, result} -> result
        {:DOWN, ^monitor, :process, ^worker, _reason} -> @failure
      after
        remaining(deadline) -> @failure
      end

    # Observing this exact process is the callback completion barrier.
    Process.exit(worker, :kill)
    stopped = await_down(worker, monitor)
    receive do: ({^operation, _late_result} -> :ok), after: (0 -> :ok)

    case stopped do
      :ok -> finish(integration, operation, result, deadline, publish_ready?)
      incomplete -> incomplete
    end
  end

  defp finish(integration, operation, result, deadline, publish_ready?)
       when result == :ok or publish_ready? == false do
    case SessionLifecycle.finish_operation(integration, operation, deadline, publish_ready?) do
      :ok -> if remaining(deadline) > 0, do: result, else: @failure
      _retired -> @failure
    end
  end

  defp finish(_integration, _operation, result, deadline, _publish_ready?),
    do: if(remaining(deadline) > 0, do: result, else: @failure)

  defp await_down(worker, monitor) do
    # The result path may already have consumed DOWN, so use a fresh monitor.
    Process.demonitor(monitor, [:flush])
    final_monitor = Process.monitor(worker)

    receive do
      {:DOWN, ^final_monitor, :process, ^worker, _reason} -> :ok
    after
      5_000 ->
        Process.demonitor(final_monitor, [:flush])
        {:error, :cleanup_incomplete}
    end
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
