defmodule Vxpipe.Identity.InstallationURLCache do
  @moduledoc "Node-local Installation URL cache with bounded, coalesced background reads."
  use GenServer

  alias Vxpipe.Identity.InstallationURL

  @call_timeout 5_000

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  def fetch(name) do
    case cached(name) do
      {:hit, result} -> result
      :miss -> call(name, :fetch)
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  @doc "Discards local data and any earlier load, then starts a fresh database read."
  def invalidate(name), do: call(name, :invalidate)

  defp call(name, message) do
    GenServer.call(name, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp cached(name) do
    case :ets.lookup(name, :public_url) do
      [{:public_url, result, expires_at, clock}] ->
        if clock.() < expires_at, do: {:hit, result}, else: :miss

      [] ->
        :miss
    end
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    options =
      Keyword.validate!(options, [
        :name,
        :task_supervisor,
        :loader,
        ttl_ms: 30_000,
        retry_ms: 1_000,
        load_timeout_ms: 2_000,
        maximum_waiters: 128,
        clock: fn -> System.monotonic_time(:millisecond) end,
        send_after: &Process.send_after/3
      ])

    state = options |> Map.new() |> Map.merge(%{job: nil, waiters: [], timer: nil})

    unless is_atom(state.name) and is_function(state.loader, 0) and
             is_function(state.clock, 0) and is_function(state.send_after, 3) and
             Enum.all?(
               [state.ttl_ms, state.retry_ms, state.maximum_waiters],
               &(is_integer(&1) and &1 > 0)
             ) and
             state.load_timeout_ms in 1..4_000 do
      raise ArgumentError, "invalid Installation URL cache configuration"
    end

    :ets.new(state.name, [:named_table, :set, :protected, read_concurrency: true])
    {:ok, schedule(state, state.ttl_ms)}
  end

  @impl true
  def handle_call(:fetch, from, state) do
    case cached(state.name) do
      {:hit, result} ->
        {:reply, result, state}

      :miss when length(state.waiters) >= state.maximum_waiters ->
        {:reply, {:error, :unavailable}, state}

      :miss ->
        {:noreply, start_load(%{state | waiters: [from | state.waiters]})}
    end
  end

  def handle_call(:invalidate, _from, state) do
    :ets.delete(state.name, :public_url)
    state = state |> cancel_load() |> start_load()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:refresh, token}, %{timer: {token, _timer}} = state),
    do: {:noreply, start_load(%{state | timer: nil})}

  def handle_info({ref, result}, %{job: %{task: %{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(state.job.timeout)
    {:noreply, finish(%{state | job: nil}, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{job: %{task: %{ref: ref}}} = state) do
    Process.cancel_timer(state.job.timeout)
    {:noreply, finish(%{state | job: nil}, {:error, :unavailable})}
  end

  def handle_info({:load_timeout, ref}, %{job: %{task: %{ref: ref}}} = state),
    do: {:noreply, state |> cancel_load() |> finish({:error, :unavailable})}

  def handle_info(_obsolete, state), do: {:noreply, state}

  defp start_load(%{job: nil} = state) do
    task = Task.Supervisor.async(state.task_supervisor, fn -> load(state.loader) end)
    timeout = state.send_after.(self(), {:load_timeout, task.ref}, state.load_timeout_ms)
    %{state | job: %{task: task, timeout: timeout}}
  catch
    :exit, _reason -> finish(state, {:error, :unavailable})
  end

  defp start_load(state), do: state

  defp cancel_load(%{job: nil} = state), do: state

  defp cancel_load(state) do
    Process.exit(state.job.task.pid, :kill)
    Process.demonitor(state.job.task.ref, [:flush])
    Process.cancel_timer(state.job.timeout)
    %{state | job: nil}
  end

  defp finish(state, result) do
    lifetime = if match?({:ok, _url}, result), do: state.ttl_ms, else: state.retry_ms
    :ets.insert(state.name, {:public_url, result, state.clock.() + lifetime, state.clock})
    Enum.each(state.waiters, &GenServer.reply(&1, result))
    schedule(%{state | waiters: []}, lifetime)
  end

  defp schedule(state, delay) do
    if state.timer, do: Process.cancel_timer(elem(state.timer, 1))
    token = make_ref()
    timer = state.send_after.(self(), {:refresh, token}, delay)
    %{state | timer: {token, timer}}
  end

  defp load(loader) do
    case loader.() do
      {:ok, %{public_url: nil}} ->
        {:ok, nil}

      {:ok, %{public_url: url}} ->
        case InstallationURL.normalize(url) do
          {:ok, ^url} -> {:ok, url}
          _invalid -> {:error, :unavailable}
        end

      _error ->
        {:error, :unavailable}
    end
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end
end
