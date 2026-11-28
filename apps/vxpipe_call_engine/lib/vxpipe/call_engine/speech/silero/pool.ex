defmodule Vxpipe.CallEngine.Speech.Silero.Pool do
  @moduledoc false
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @impl true
  def init(opts), do: {:ok, %{budget: Keyword.fetch!(opts, :budget), workers: %{}}}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{budget: state.budget, active_workers: map_size(state.workers)}, state}
  end

  def handle_call(:register_worker, {pid, _}, state) do
    {:reply, :ok, %{state | workers: Map.put(state.workers, pid, Process.monitor(pid))}}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, pid, _}, state) do
    case state.workers do
      %{^pid => ^monitor} -> {:noreply, %{state | workers: Map.delete(state.workers, pid)}}
      _ -> {:noreply, state}
    end
  end
end
