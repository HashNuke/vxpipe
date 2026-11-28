defmodule Vxpipe.CallEngine.Speech.Silero.Pool do
  @moduledoc false
  use GenServer
  alias Vxpipe.CallEngine.Speech.Silero.Lease

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  def reserve(generation, deadline, server \\ __MODULE__) do
    remaining = deadline - System.monotonic_time(:millisecond)

    with true <- remaining > 0,
         {:ok, lease} <- Lease.offer(server, generation) do
      try do
        GenServer.call(lease.pool, {:adopt, lease, deadline}, remaining)
      catch
        :exit, _ ->
          GenServer.cast(lease.pool, {:abandon, lease})
          {:error, :model_unavailable}
      end
    else
      false -> {:error, :model_unavailable}
      error -> error
    end
  end

  def close(%Lease{} = lease) do
    GenServer.call(lease.pool, {:close, lease})
  catch
    :exit, _ -> {:error, :unknown_lease}
  end

  @impl true
  def init(opts) do
    budget = Keyword.fetch!(opts, :budget)
    capacity = budget.workers * Keyword.get(opts, :leases_per_worker, 128)
    table = Lease.open_table(Keyword.fetch!(opts, :name), capacity)
    {:ok, %{budget: budget, workers: %{}, table: table, capacity: capacity, leases: %{}}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply,
     %{
       budget: state.budget,
       active_workers: map_size(state.workers),
       admitted: map_size(state.leases),
       admission_limit: state.capacity
     }, state}
  end

  def handle_call({:adopt, lease, deadline}, {owner, _}, state) do
    if owner == lease.owner and lease.table == state.table and
         System.monotonic_time(:millisecond) < deadline and Lease.adopt(lease) do
      monitor = Process.monitor(owner)
      {:reply, {:ok, lease}, put_in(state.leases[lease.token], {lease, monitor})}
    else
      Lease.withdraw(lease)
      {:reply, {:error, :model_unavailable}, state}
    end
  end

  def handle_call({:close, lease}, {owner, _}, state) do
    case state.leases[lease.token] do
      {^lease, _monitor} when lease.owner == owner -> {:reply, :ok, release(state, lease)}
      _ -> {:reply, {:error, :unknown_lease}, state}
    end
  end

  def handle_call(:register_worker, {pid, _}, state) do
    {:reply, :ok, %{state | workers: Map.put(state.workers, pid, Process.monitor(pid))}}
  end

  @impl true
  def handle_cast({:abandon, lease}, state) do
    {:noreply, release(state, lease)}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, pid, _}, state) do
    case state.workers do
      %{^pid => ^monitor} ->
        {:noreply, %{state | workers: Map.delete(state.workers, pid)}}

      _ ->
        case Enum.find_value(state.leases, fn {_id, {lease, ref}} ->
               if ref == monitor, do: lease
             end) do
          nil -> {:noreply, state}
          lease -> {:noreply, release(state, lease)}
        end
    end
  end

  defp release(state, lease) do
    case Map.pop(state.leases, lease.token) do
      {nil, _} ->
        state

      {{_, monitor}, leases} ->
        Process.demonitor(monitor, [:flush])
        Lease.release(lease)
        %{state | leases: leases}
    end
  end
end
