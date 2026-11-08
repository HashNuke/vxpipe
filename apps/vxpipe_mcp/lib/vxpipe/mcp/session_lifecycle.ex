defmodule Vxpipe.MCP.SessionLifecycle do
  @moduledoc false

  use GenServer, restart: :temporary

  def name(integration),
    do: {:via, Registry, {Vxpipe.MCP.ConnectionRegistry, {:session_lifecycle, integration}}}

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: name(Keyword.fetch!(opts, :integration)))

  def ready(integration), do: GenServer.call(name(integration), :ready, 500)

  # Order startup abandonment with publication by another opener or lookup.
  def abandon_start(integration) do
    GenServer.call(name(integration), :abandon_start, 500)
  catch
    :exit, {:timeout, _call} -> {:error, :cleanup_incomplete}
    :exit, _gone -> :retire
  end

  def prepare_operation(integration, deadline, watch \\ []),
    do: operation_call(integration, {:prepare_operation, deadline, watch}, deadline)

  def claim_operation(integration, operation, deadline),
    do: operation_call(integration, {:claim_operation, operation}, deadline)

  def finish_operation(integration, operation, deadline, publish_ready? \\ true),
    do: operation_call(integration, {:finish_operation, operation, publish_ready?}, deadline)

  # A shared admission coordinator may shorten a worker's budget, never extend it.
  def constrain_operation(integration, deadline),
    do: operation_call(integration, {:constrain_operation, deadline}, deadline)

  def cancel_operation(integration, operation),
    do: GenServer.cast(name(integration), {:cancel_operation, operation})

  defp operation_call(integration, request, deadline),
    do: GenServer.call(name(integration), request, max(min(deadline - now(), 500), 1))

  def begin_close(integration, client, caller, deadline),
    do:
      GenServer.call(
        name(integration),
        {:begin_close, client, caller, deadline},
        max(deadline - now(), 1)
      )

  def admit(integration, method, stage, permission) do
    GenServer.call(name(integration), {:admit, method, stage, permission}, 500)
  catch
    :exit, _reason -> {:error, :session_retired}
  end

  @impl true
  def init(opts) do
    caller = Keyword.fetch!(opts, :caller)
    host = Keyword.fetch!(opts, :host)
    deadline = Keyword.fetch!(opts, :deadline)

    if now() < deadline and Process.alive?(caller) and Process.alive?(host) do
      {:ok,
       %{
         integration: Keyword.fetch!(opts, :integration),
         caller: caller,
         host: host,
         monitors: [Process.monitor(caller), Process.monitor(host)],
         deadline: deadline,
         timer: Process.send_after(self(), :expired, max(deadline - now(), 0)),
         phase: :starting,
         client: nil,
         permission: nil,
         submitted: false,
         operations: %{}
       }}
    else
      {:stop, :connection_failed}
    end
  end

  @impl true
  def handle_call(:ready, _from, %{phase: :active} = state), do: {:reply, :ok, state}

  def handle_call(:ready, _from, %{phase: :closing} = state),
    do: {:reply, {:error, :connection_failed}, state}

  def handle_call(:ready, from, state) do
    if now() < state.deadline and Process.alive?(state.caller) and Process.alive?(state.host) do
      {:reply, :ok, activate(state)}
    else
      GenServer.reply(from, {:error, :connection_failed})
      cancel(state)
    end
  end

  def handle_call({:begin_close, _client, _caller, _deadline}, _from, %{phase: :closing} = state),
    do: {:reply, :closing, state}

  def handle_call(:abandon_start, _from, %{phase: :active} = state),
    do: {:reply, :retained, state}

  def handle_call(:abandon_start, _from, %{phase: :closing} = state),
    do: {:reply, :retire, state}

  def handle_call(:abandon_start, _from, state) do
    state = Enum.reduce(Map.keys(state.operations), state, &cancel_operation_state(&2, &1))
    Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :retirement_expired, max(state.deadline - now(), 0))
    {:reply, :retire, %{state | phase: :closing, timer: timer}}
  end

  def handle_call({:begin_close, client, caller, deadline}, _from, state) do
    state = Enum.reduce(Map.keys(state.operations), state, &cancel_operation_state(&2, &1))
    if state.timer, do: Process.cancel_timer(state.timer)
    Enum.each(state.monitors, &Process.demonitor(&1, [:flush]))
    permission = make_ref()

    next = %{
      state
      | phase: :closing,
        client: client,
        caller: caller,
        monitors: [Process.monitor(caller)],
        deadline: deadline,
        permission: permission,
        timer: Process.send_after(self(), :retirement_expired, max(deadline - now(), 0))
    }

    {:reply, {:ok, permission}, next}
  end

  def handle_call({:prepare_operation, deadline, watch}, {caller, _tag}, state) do
    if operation_allowed?(state, caller, deadline) and Enum.all?(watch, &Process.alive?/1) do
      operation = make_ref()

      pending = %{
        caller: caller,
        caller_ref: Process.monitor(caller),
        watched: Map.new(watch, &{Process.monitor(&1), &1}),
        deadline: deadline,
        timer:
          Process.send_after(self(), {:operation_expired, operation}, max(deadline - now(), 0)),
        worker: nil,
        worker_ref: nil
      }

      {:reply, {:ok, operation},
       %{state | operations: Map.put(state.operations, operation, pending)}}
    else
      {:reply, {:error, :connection_failed}, state}
    end
  end

  def handle_call({:claim_operation, operation}, {worker, _tag}, state) do
    case Map.get(state.operations, operation) do
      %{worker: nil} = pending ->
        if pending_allowed?(state, pending) do
          claimed = %{pending | worker: worker, worker_ref: Process.monitor(worker)}
          {:reply, :ok, %{state | operations: Map.put(state.operations, operation, claimed)}}
        else
          {:reply, {:error, :connection_failed}, cancel_operation_state(state, operation)}
        end

      _missing ->
        {:reply, {:error, :connection_failed}, state}
    end
  end

  def handle_call({:finish_operation, operation, publish_ready?}, {caller, _tag}, state) do
    case Map.get(state.operations, operation) do
      %{caller: ^caller, worker: worker} = pending when is_pid(worker) ->
        allowed =
          pending_allowed?(state, pending) and not Process.alive?(worker)

        next = cancel_operation_state(state, operation)

        if allowed,
          do: {:reply, :ok, if(publish_ready?, do: activate(next), else: next)},
          else: {:reply, {:error, :connection_failed}, next}

      _missing ->
        {:reply, {:error, :connection_failed}, state}
    end
  end

  def handle_call({:constrain_operation, deadline}, {worker, _tag}, state) do
    case Enum.find(state.operations, fn {_operation, pending} -> pending.worker == worker end) do
      {operation, pending} ->
        constrained = %{pending | deadline: min(pending.deadline, deadline)}

        if pending_allowed?(state, constrained) do
          Process.cancel_timer(pending.timer)

          timer =
            Process.send_after(
              self(),
              {:operation_expired, operation},
              max(constrained.deadline - now(), 0)
            )

          next = %{constrained | timer: timer}
          {:reply, :ok, %{state | operations: Map.put(state.operations, operation, next)}}
        else
          {:reply, {:error, :connection_failed}, cancel_operation_state(state, operation)}
        end

      nil ->
        {:reply, {:error, :connection_failed}, state}
    end
  end

  def handle_call({:admit, method, stage, permission}, _from, state) do
    allowed =
      case state.phase do
        :active ->
          true

        :starting ->
          now() < state.deadline and Process.alive?(state.caller) and Process.alive?(state.host)

        :closing ->
          method == :delete and permission == state.permission and
            not state.submitted and now() < state.deadline and Process.alive?(state.caller)
      end

    if allowed do
      submitted = state.submitted or (state.phase == :closing and stage == :submit)
      {:reply, :ok, %{state | submitted: submitted}}
    else
      {:reply, {:error, :session_retired}, state}
    end
  end

  @impl true
  def handle_cast({:cancel_operation, operation}, state),
    do: {:noreply, cancel_operation_state(state, operation)}

  @impl true
  def handle_info(:retirement_expired, %{phase: :closing} = state), do: cancel(state)

  def handle_info(:expired, %{phase: :starting} = state), do: cancel(state)

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state.monitors do
      cancel(state)
    else
      next =
        Enum.reduce(state.operations, state, fn {operation, pending}, acc ->
          if pending.caller_ref == ref or Map.has_key?(pending.watched, ref),
            do: cancel_operation_state(acc, operation),
            else: acc
        end)

      {:noreply, next}
    end
  end

  def handle_info({:operation_expired, operation}, state),
    do: {:noreply, cancel_operation_state(state, operation)}

  def handle_info(_stale, state), do: {:noreply, state}

  defp cancel(state) do
    if is_pid(state.client), do: Process.exit(state.client, :kill)
    Process.exit(state.integration, :kill)
    {:noreply, state}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp operation_allowed?(state, caller, deadline) do
    state.phase != :closing and now() < deadline and Process.alive?(caller) and
      Process.alive?(state.host) and
      (state.phase == :active or (now() < state.deadline and Process.alive?(state.caller)))
  end

  defp pending_allowed?(state, pending) do
    operation_allowed?(state, pending.caller, pending.deadline) and
      Enum.all?(pending.watched, fn {_ref, pid} -> Process.alive?(pid) end)
  end

  defp activate(%{phase: :active} = state), do: state

  defp activate(state) do
    Process.cancel_timer(state.timer)
    Enum.each(state.monitors, &Process.demonitor(&1, [:flush]))
    %{state | phase: :active, monitors: [], timer: nil}
  end

  defp cancel_operation_state(state, operation) do
    case Map.pop(state.operations, operation) do
      {nil, _remaining} ->
        state

      {pending, remaining} ->
        if pending.worker, do: Process.exit(pending.worker, :kill)
        if pending.worker_ref, do: Process.demonitor(pending.worker_ref, [:flush])
        Process.demonitor(pending.caller_ref, [:flush])
        Enum.each(pending.watched, fn {ref, _pid} -> Process.demonitor(ref, [:flush]) end)
        Process.cancel_timer(pending.timer)
        %{state | operations: remaining}
    end
  end
end
