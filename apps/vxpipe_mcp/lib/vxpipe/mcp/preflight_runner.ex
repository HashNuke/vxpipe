defmodule Vxpipe.MCP.PreflightRunner do
  @moduledoc "Bounds active preflight operations, tenant request frequency and whole-operation lifetime."
  use GenServer

  alias Vxpipe.MCP.{SessionLifecycle, SessionOperation}

  @call_timeout 20_000

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))

  def run(server \\ __MODULE__, tenant, operation),
    do: GenServer.call(server, {:run, tenant, operation, now()}, @call_timeout)

  @doc "Runs protocol work inside its session; this runner grants capacity only."
  def run_owned(server, tenant, integration, operation) do
    entered = now()

    with runner when is_pid(runner) <- GenServer.whereis(server),
         [{^runner, timeout}] <-
           Registry.lookup(Vxpipe.MCP.ConnectionRegistry, {__MODULE__, runner}) do
      SessionOperation.run(
        integration,
        entered + min(timeout, @call_timeout),
        fn ->
          with {:ok, deadline} <-
                 GenServer.call(runner, {:permit, tenant, entered}, @call_timeout),
               :ok <- SessionLifecycle.constrain_operation(integration, deadline) do
            safe_run(operation)
          end
        end,
        publish_ready?: false,
        watch: [runner]
      )
    else
      _missing -> {:error, :mcp_discovery_unavailable}
    end
  end

  @impl true
  def init(options) do
    timeout = Keyword.get(options, :timeout, 15_000)
    {:ok, _} = Registry.register(Vxpipe.MCP.ConnectionRegistry, {__MODULE__, self()}, timeout)

    {:ok,
     %{
       jobs: %{},
       recent: %{},
       task_supervisor: Keyword.fetch!(options, :task_supervisor),
       limit: Keyword.get(options, :limit, 8),
       timeout: timeout,
       interval: Keyword.get(options, :interval, 500)
     }}
  end

  @impl true
  def handle_call({:run, tenant, operation, entered}, from, state) do
    caller = elem(from, 0)

    case admit(state, tenant, caller, entered) do
      {:ok, deadline, state} ->
        task =
          Task.Supervisor.async_nolink(state.task_supervisor, fn ->
            if Process.alive?(caller) and now() < deadline,
              do: safe_run(operation),
              else: {:error, :mcp_connection_timed_out}
          end)

        owner = Process.monitor(caller)
        timer = Process.send_after(self(), {:expired, task.ref}, max(deadline - now(), 0))
        job = %{task: task, owner: owner, timer: timer, from: from, deadline: deadline}
        {:noreply, %{state | jobs: Map.put(state.jobs, task.ref, job)}}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:permit, tenant, entered}, {worker, _tag}, state) do
    case admit(state, tenant, worker, entered) do
      {:ok, deadline, state} ->
        monitor = Process.monitor(worker)
        timer = Process.send_after(self(), {:expired, monitor}, max(deadline - now(), 0))
        job = %{worker: worker, owner: monitor, timer: timer}
        {:reply, {:ok, deadline}, %{state | jobs: Map.put(state.jobs, monitor, job)}}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.fetch(state.jobs, ref) do
      {:ok, %{from: from, deadline: deadline} = job} ->
        result = if now() < deadline, do: result, else: {:error, :mcp_connection_timed_out}
        GenServer.reply(from, result)
        {:noreply, remove(state, ref, job)}

      _missing ->
        {:noreply, state}
    end
  end

  def handle_info({:expired, ref}, state) do
    case Map.fetch(state.jobs, ref) do
      {:ok, job} ->
        stop(job)
        reply(job, {:error, :mcp_connection_timed_out})
        {:noreply, remove(state, ref, job)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.jobs, fn {task_ref, job} -> ref == task_ref or ref == job.owner end) do
      {task_ref, job} ->
        stop(job)
        if ref == task_ref, do: reply(job, {:error, :mcp_discovery_unavailable})
        {:noreply, remove(state, task_ref, job)}

      nil ->
        {:noreply, state}
    end
  end

  defp admit(state, tenant, caller, entered) do
    time = now()
    recent = Map.reject(state.recent, fn {_key, expiry} -> expiry <= time end)
    state = %{state | recent: recent}
    deadline = min(entered + state.timeout, entered + @call_timeout)

    cond do
      not Process.alive?(caller) or time >= deadline ->
        {:error, :mcp_connection_timed_out, state}

      map_size(state.jobs) >= state.limit or Map.has_key?(recent, tenant) or
          map_size(recent) >= 1024 ->
        {:error, :mcp_connection_busy, state}

      true ->
        {:ok, deadline, %{state | recent: Map.put(recent, tenant, time + state.interval)}}
    end
  end

  defp stop(%{task: task}), do: Task.shutdown(task, :brutal_kill)
  defp stop(%{worker: worker}), do: Process.exit(worker, :kill)

  defp reply(%{from: from}, result), do: GenServer.reply(from, result)
  defp reply(_permit, _result), do: :ok

  defp remove(state, ref, job) do
    Process.cancel_timer(job.timer)
    Process.demonitor(ref, [:flush])
    Process.demonitor(job.owner, [:flush])
    %{state | jobs: Map.delete(state.jobs, ref)}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp safe_run(operation) do
    operation.()
  rescue
    _exception -> {:error, :mcp_discovery_unavailable}
  catch
    _kind, _reason -> {:error, :mcp_discovery_unavailable}
  end
end
