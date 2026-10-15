defmodule Vxpipe.Gateway.CallCleanupReconciler do
  @moduledoc "Bounded, restartable traversal of durable call cleanup work."

  use GenServer

  alias Vxpipe.Calls
  alias Vxpipe.Gateway.CallCleanupRecovery

  @task_supervisor Vxpipe.Gateway.AdmissionTaskSupervisor
  @defaults [page_size: 25, concurrency: 4, timeout_ms: 5_000, interval_ms: 5_000, retry_ms: 250]

  def start_link(options) do
    {name, options} = Keyword.pop(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(is_nil(name), do: [], else: [name: name]))
  end

  # A wake is only a scheduling hint. Durable intent survives a missing/restarting
  # reconciler, and callers never own the resulting cleanup tasks.
  def wake(server \\ __MODULE__), do: GenServer.cast(server, :wake)

  @impl true
  def init(options) do
    with {:ok, settings} <- settings(options) do
      {:ok,
       %{
         settings: settings,
         tasks: %{},
         queue: [],
         cursor: nil,
         timer: nil,
         wake?: false,
         retry_ms: settings.retry_ms
       }, {:continue, :scan}}
    else
      error -> {:stop, error}
    end
  end

  @impl true
  def handle_continue(:scan, state), do: {:noreply, scan(state)}

  @impl true
  def handle_cast(:wake, %{tasks: tasks, queue: []} = state) when map_size(tasks) == 0,
    do: {:noreply, state |> cancel_timer() |> scan()}

  def handle_cast(:wake, state), do: {:noreply, %{state | wake?: true}}

  @impl true
  def handle_info({:scan_cleanup, token}, %{timer: {token, _timer}} = state),
    do: {:noreply, scan(%{state | timer: nil})}

  def handle_info({reference, result}, state) when is_reference(reference) do
    tasks =
      case Map.fetch(state.tasks, reference) do
        {:ok, %{kind: :scan} = job} -> Map.put(state.tasks, reference, %{job | result: result})
        _row_or_unknown -> state.tasks
      end

    {:noreply, %{state | tasks: tasks}}
  end

  def handle_info({:DOWN, reference, :process, worker, reason}, state) do
    case Map.fetch(state.tasks, reference) do
      {:ok, %{task: %Task{pid: ^worker}} = job} ->
        state = %{state | tasks: Map.delete(state.tasks, reference)}
        {:noreply, finished(state, job, reason)}

      _unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp finished(state, %{kind: :scan, result: {:ok, page}}, :normal) do
    %{state | queue: page.items, cursor: page.next_cursor, retry_ms: state.settings.retry_ms}
    |> dispatch()
  end

  defp finished(state, %{kind: :scan}, _reason) do
    delay = state.retry_ms
    schedule(%{state | retry_ms: min(delay * 2, 5_000)}, delay)
  end

  # Even uncertain/failed rows advance this finite traversal. A later cycle
  # revisits their durable intent instead of starving the rest of the page.
  defp finished(state, %{kind: :row}, _reason), do: dispatch(state)

  defp scan(state) do
    cursor = state.cursor
    settings = state.settings

    start_task(state, :scan, fn ->
      Calls.scan_call_cleanup(cursor, settings.page_size, settings.calls_options)
    end)
  end

  defp dispatch(%{queue: [row | rest], tasks: tasks, settings: settings} = state)
       when map_size(tasks) < settings.concurrency do
    state =
      start_task(%{state | queue: rest}, :row, fn ->
        _result = CallCleanupRecovery.reconcile(row, settings.calls_options)
        :ok
      end)

    dispatch(state)
  end

  defp dispatch(%{queue: [], tasks: tasks} = state) when map_size(tasks) == 0 do
    cond do
      not is_nil(state.cursor) -> scan(state)
      state.wake? -> scan(%{state | wake?: false})
      true -> schedule(state, state.settings.interval_ms)
    end
  end

  defp dispatch(state), do: state

  defp start_task(state, kind, operation) do
    timeout = state.settings.timeout_ms

    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        {:ok, timer} = :timer.kill_after(timeout, self())

        try do
          operation.()
        after
          :timer.cancel(timer)
        end
      end)

    job = %{task: task, kind: kind, result: nil}
    %{state | tasks: Map.put(state.tasks, task.ref, job)}
  end

  defp schedule(state, delay) do
    token = make_ref()
    timer = Process.send_after(self(), {:scan_cleanup, token}, delay)
    %{state | timer: {token, timer}}
  end

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(%{timer: {_token, timer}} = state) do
    Process.cancel_timer(timer)
    %{state | timer: nil}
  end

  defp settings(options) do
    values = Map.new(Keyword.merge(@defaults, options))
    calls_options = Map.get(values, :calls_options, [])

    if valid_range?(values.page_size, 1..100) and valid_range?(values.concurrency, 1..16) and
         valid_range?(values.timeout_ms, 1..30_000) and
         valid_range?(values.interval_ms, 1..60_000) and
         valid_range?(values.retry_ms, 1..5_000) and is_list(calls_options) and
         Keyword.keyword?(calls_options),
       do: {:ok, Map.put(values, :calls_options, calls_options)},
       else: {:error, :invalid_cleanup_reconciliation_options}
  end

  defp valid_range?(value, range), do: is_integer(value) and value in range
end
