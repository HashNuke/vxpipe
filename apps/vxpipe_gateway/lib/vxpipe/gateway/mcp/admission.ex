defmodule Vxpipe.Gateway.MCP.Admission do
  @moduledoc "Bounds active MCP HTTP requests and releases leases when their owners exit."
  use GenServer

  def start_link(options) do
    {name, options} = Keyword.pop(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  def acquire(server), do: safe_call(server, :acquire)
  def release(server, lease), do: safe_call(server, {:release, lease})

  @impl true
  def init(options) do
    maximum = Keyword.get(options, :max_concurrency, 64)

    if not (is_integer(maximum) and maximum > 0),
      do: raise(ArgumentError, "invalid MCP concurrency limit")

    {:ok, %{maximum: maximum, leases: %{}}}
  end

  @impl true
  def handle_call(:acquire, {owner, _tag}, state) do
    if map_size(state.leases) < state.maximum do
      lease = Process.monitor(owner)
      {:reply, {:ok, lease}, %{state | leases: Map.put(state.leases, lease, owner)}}
    else
      {:reply, {:error, :overloaded}, state}
    end
  end

  def handle_call({:release, lease}, {owner, _tag}, state) do
    if Map.get(state.leases, lease) == owner do
      Process.demonitor(lease, [:flush])
      {:reply, :ok, %{state | leases: Map.delete(state.leases, lease)}}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, lease, :process, _owner, _reason}, state) do
    {:noreply, %{state | leases: Map.delete(state.leases, lease)}}
  end

  defp safe_call(server, request) do
    GenServer.call(server, request, 1_000)
  catch
    :exit, _reason -> {:error, :unavailable}
  end
end
