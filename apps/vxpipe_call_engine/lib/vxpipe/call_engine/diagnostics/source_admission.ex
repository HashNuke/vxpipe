defmodule Vxpipe.CallEngine.Diagnostics.SourceAdmission do
  @moduledoc "Node-wide source slots retained through room-owned worker termination."
  use GenServer
  alias Vxpipe.CallEngine.Diagnostics.AttachmentLease

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :name))

  def reserve(pool, owner), do: call(pool, {:reserve, owner})

  def adopt(pool, lease) do
    case call(pool, {:adopt, lease}) do
      :ok ->
        :ok

      error ->
        AttachmentLease.cancel(lease)
        error
    end
  end

  def cancel(pool, lease) do
    AttachmentLease.cancel(lease)
    call(pool, {:cancel, lease})
  end

  def status(pool), do: call(pool, :status)

  @doc "Starts and tracks the worker before binding/adoption; failure waits for worker termination."
  def start_worker(pool, lease, workers, spec) do
    AttachmentLease.operation(lease, fn ->
      with :ok <- call(pool, {:begin_start, lease}) do
        case start_child(workers, spec, lease) do
          {:ok, worker} ->
            case call(pool, {:track, lease, worker}) do
              :ok ->
                {:ok, worker}

              _ ->
                stop_worker(worker)
                cancel_attempt(pool, lease)
                {:error, :unavailable}
            end

          error ->
            cancel_attempt(pool, lease)
            error
        end
      end
    end)
  end

  defp start_child(workers, spec, lease) do
    case DynamicSupervisor.start_child(workers, spec) do
      {:ok, worker, _info} -> {:ok, worker}
      result -> result
    end
  catch
    :exit, _ ->
      # An interrupted start may have created a child whose pid was never returned.
      AttachmentLease.abandon(lease)
      {:error, :unavailable}
  end

  defp stop_worker(worker) do
    monitor = Process.monitor(worker)
    Process.exit(worker, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^worker, _} -> :ok
    end
  end

  defp cancel_attempt(pool, lease) do
    if cancel(pool, lease) != :ok do
      AttachmentLease.cancel(lease)
      AttachmentLease.finish(lease)
    end
  end

  defp call(pool, message) do
    GenServer.call(pool, message, 250)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @impl true
  def init(options), do: {:ok, %{gate: Keyword.fetch!(options, :gate), entries: %{}}}

  @impl true
  def handle_call({:reserve, owner}, _from, state) do
    state = prune(state)

    case AttachmentLease.reserve(state.gate, owner) do
      {:ok, lease} ->
        entry = %{
          lease: lease,
          owner_monitor: Process.monitor(owner),
          worker: nil,
          worker_monitor: nil,
          adopted?: false,
          starting?: false,
          timer:
            Process.send_after(self(), {:expire, lease.state}, AttachmentLease.remaining(lease))
        }

        {:reply, {:ok, lease}, put_in(state.entries[lease.state], entry)}

      _ ->
        {:reply, {:error, :capacity_unavailable}, state}
    end
  end

  def handle_call({:begin_start, lease}, _from, state) do
    case Map.get(state.entries, lease.state) do
      %{lease: ^lease, starting?: false} = entry ->
        if AttachmentLease.current?(lease) do
          {:reply, :ok, put_in(state.entries[lease.state], %{entry | starting?: true})}
        else
          {:reply, {:error, :unavailable}, revoke(state, lease.state)}
        end

      _ ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:track, lease, worker}, _from, state) do
    case Map.get(state.entries, lease.state) do
      %{lease: ^lease, worker: nil, starting?: true} = entry when is_pid(worker) ->
        if AttachmentLease.current?(lease) and node(worker) == node() do
          entry = %{entry | worker: worker, worker_monitor: Process.monitor(worker)}
          {:reply, :ok, put_in(state.entries[lease.state], entry)}
        else
          {:reply, {:error, :unavailable}, state}
        end

      _ ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:adopt, lease}, _from, state) do
    state = prune(state)

    case Map.get(state.entries, lease.state) do
      %{lease: ^lease, worker: worker, adopted?: false} = entry when is_pid(worker) ->
        if AttachmentLease.adopt(lease) do
          Process.cancel_timer(entry.timer)
          {:reply, :ok, put_in(state.entries[lease.state], %{entry | adopted?: true})}
        else
          {:reply, {:error, :unavailable}, revoke(state, lease.state)}
        end

      _ ->
        {:reply, {:error, :unavailable}, state}
    end
  end

  def handle_call({:cancel, lease}, _from, state),
    do: {:reply, :ok, revoke(state, lease.state)}

  def handle_call(:status, _from, state) do
    state = prune(state)

    {:reply,
     %{
       active_sources: Enum.count(state.entries, fn {_, entry} -> entry.adopted? end),
       occupied_slots: AttachmentLease.pending(state.gate)
     }, state}
  end

  @impl true
  def handle_info({:expire, key}, state) do
    case Map.get(state.entries, key) do
      %{adopted?: false} -> {:noreply, revoke(state, key)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _, _}, state) do
    state =
      Enum.reduce(state.entries, state, fn {key, entry}, acc ->
        cond do
          entry.worker_monitor == monitor -> remove(acc, key)
          entry.owner_monitor == monitor -> revoke(acc, key)
          true -> acc
        end
      end)

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted, log: []}

  defp prune(state) do
    Enum.reduce(state.entries, state, fn {key, entry}, acc ->
      cond do
        entry.worker != nil and not Process.alive?(entry.worker) -> remove(acc, key)
        not AttachmentLease.current?(entry.lease) -> revoke(acc, key)
        true -> acc
      end
    end)
  end

  defp revoke(state, key) do
    case Map.get(state.entries, key) do
      nil ->
        state

      entry ->
        AttachmentLease.cancel(entry.lease)
        if entry.worker == nil, do: remove(state, key), else: state
    end
  end

  defp remove(state, key) do
    {entry, entries} = Map.pop(state.entries, key)
    AttachmentLease.cancel(entry.lease)
    AttachmentLease.finish(entry.lease)
    Process.cancel_timer(entry.timer)
    Process.demonitor(entry.owner_monitor, [:flush])
    if entry.worker_monitor, do: Process.demonitor(entry.worker_monitor, [:flush])
    %{state | entries: entries}
  end
end
