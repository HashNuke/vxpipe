defmodule Vxpipe.MCP.PreflightRunner do
  @moduledoc "Bounds active preflight operations, tenant request frequency and whole-operation lifetime."
  use GenServer

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))

  def run(server \\ __MODULE__, tenant, operation),
    do: GenServer.call(server, {:run, tenant, operation}, 20_000)

  @impl true
  def init(options) do
    {:ok,
     %{
       jobs: %{},
       recent: %{},
       task_supervisor: Keyword.fetch!(options, :task_supervisor),
       limit: Keyword.get(options, :limit, 8),
       timeout: Keyword.get(options, :timeout, 15_000),
       interval: Keyword.get(options, :interval, 500)
     }}
  end

  @impl true
  def handle_call({:run, tenant, operation}, from, state) do
    now = System.monotonic_time(:millisecond)
    recent = Map.reject(state.recent, fn {_key, expiry} -> expiry <= now end)
    state = %{state | recent: recent}

    if map_size(state.jobs) >= state.limit or Map.has_key?(recent, tenant) or
         map_size(recent) >= 1024 do
      {:reply, {:error, :mcp_connection_busy}, state}
    else
      task = Task.Supervisor.async_nolink(state.task_supervisor, fn -> safe_run(operation) end)
      owner = Process.monitor(elem(from, 0))
      timer = Process.send_after(self(), {:expired, task.ref}, state.timeout)
      job = %{task: task, owner: owner, timer: timer, from: from, deadline: now + state.timeout}

      {:noreply,
       %{
         state
         | jobs: Map.put(state.jobs, task.ref, job),
           recent: Map.put(recent, tenant, now + state.interval)
       }}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    case Map.fetch(state.jobs, ref) do
      {:ok, job} ->
        result =
          if System.monotonic_time(:millisecond) < job.deadline,
            do: result,
            else: {:error, :mcp_connection_timed_out}

        GenServer.reply(job.from, result)
        {:noreply, remove(state, ref, job)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:expired, ref}, state) do
    case Map.fetch(state.jobs, ref) do
      {:ok, job} ->
        Task.shutdown(job.task, :brutal_kill)
        GenServer.reply(job.from, {:error, :mcp_connection_timed_out})
        {:noreply, remove(state, ref, job)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.jobs, fn {task_ref, job} -> ref == task_ref or ref == job.owner end) do
      {task_ref, job} ->
        Task.shutdown(job.task, :brutal_kill)
        if ref == task_ref, do: GenServer.reply(job.from, {:error, :mcp_discovery_unavailable})
        {:noreply, remove(state, task_ref, job)}

      nil ->
        {:noreply, state}
    end
  end

  defp remove(state, ref, job) do
    Process.cancel_timer(job.timer)
    Process.demonitor(ref, [:flush])
    Process.demonitor(job.owner, [:flush])
    %{state | jobs: Map.delete(state.jobs, ref)}
  end

  defp safe_run(operation) do
    operation.()
  rescue
    _exception -> {:error, :mcp_discovery_unavailable}
  catch
    _kind, _reason -> {:error, :mcp_discovery_unavailable}
  end
end
