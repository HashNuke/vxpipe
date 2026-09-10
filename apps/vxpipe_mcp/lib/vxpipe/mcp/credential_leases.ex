defmodule Vxpipe.MCP.CredentialLeases do
  @moduledoc false

  use GenServer

  alias Vxpipe.MCP.ConnectionKey

  @revoked_message :vxpipe_mcp_credential_revoked

  defstruct holders: %{}, leases: %{}, revoked: MapSet.new()

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec acquire([ConnectionKey.t()]) ::
          :ok | {:error, :credential_revoked | :invalid_lease}
  def acquire(keys) when is_list(keys) do
    GenServer.call(__MODULE__, {:acquire, self(), keys})
  end

  @spec revoke(ConnectionKey.t()) :: :ok
  def revoke(%ConnectionKey{} = key) do
    GenServer.call(__MODULE__, {:revoke, key})
  end

  @spec revoked?(ConnectionKey.t()) :: boolean()
  def revoked?(%ConnectionKey{} = key) do
    GenServer.call(__MODULE__, {:revoked?, key})
  end

  @spec active_count(ConnectionKey.t()) :: non_neg_integer()
  def active_count(%ConnectionKey{} = key) do
    GenServer.call(__MODULE__, {:active_count, key})
  end

  @impl true
  def init(_options), do: {:ok, %__MODULE__{}}

  @impl true
  def handle_call({:acquire, holder, keys}, _from, %__MODULE__{} = state) do
    keys = MapSet.new(keys)

    cond do
      Enum.any?(keys, &(not match?(%ConnectionKey{}, &1))) ->
        {:reply, {:error, :invalid_lease}, state}

      not MapSet.disjoint?(keys, state.revoked) ->
        {:reply, {:error, :credential_revoked}, state}

      true ->
        {:reply, :ok, add_lease(state, holder, keys)}
    end
  end

  def handle_call({:revoke, key}, _from, %__MODULE__{} = state) do
    holders = Map.get(state.leases, key, MapSet.new())
    Enum.each(holders, &send(&1, {@revoked_message, key}))

    state =
      state
      |> Map.update!(:revoked, &MapSet.put(&1, key))
      |> invalidate_lease(key, holders)

    {:reply, :ok, state}
  end

  def handle_call({:revoked?, key}, _from, %__MODULE__{} = state) do
    {:reply, MapSet.member?(state.revoked, key), state}
  end

  def handle_call({:active_count, key}, _from, %__MODULE__{} = state) do
    count = state.leases |> Map.get(key, MapSet.new()) |> Enum.count(&Process.alive?/1)
    {:reply, count, state}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, holder, _reason}, %__MODULE__{} = state) do
    case Map.get(state.holders, holder) do
      %{monitor: ^reference, keys: keys} ->
        {:noreply, remove_holder(state, holder, keys)}

      _unknown ->
        {:noreply, state}
    end
  end

  defp add_lease(state, holder, keys) do
    case Map.get(state.holders, holder) do
      nil ->
        monitor = Process.monitor(holder)
        holders = Map.put(state.holders, holder, %{keys: keys, monitor: monitor})
        leases = Enum.reduce(keys, state.leases, &add_holder(&2, &1, holder))
        %{state | holders: holders, leases: leases}

      %{keys: current} = lease ->
        added = MapSet.difference(keys, current)
        holders = Map.put(state.holders, holder, %{lease | keys: MapSet.union(current, keys)})
        leases = Enum.reduce(added, state.leases, &add_holder(&2, &1, holder))
        %{state | holders: holders, leases: leases}
    end
  end

  defp add_holder(leases, key, holder) do
    Map.update(leases, key, MapSet.new([holder]), &MapSet.put(&1, holder))
  end

  defp invalidate_lease(state, key, holders) do
    state = %{state | leases: Map.delete(state.leases, key)}

    Enum.reduce(holders, state, fn holder, state ->
      case Map.get(state.holders, holder) do
        %{keys: keys, monitor: monitor} = lease ->
          remaining = MapSet.delete(keys, key)

          if MapSet.size(remaining) == 0 do
            Process.demonitor(monitor, [:flush])
            %{state | holders: Map.delete(state.holders, holder)}
          else
            holders = Map.put(state.holders, holder, %{lease | keys: remaining})
            %{state | holders: holders}
          end

        nil ->
          state
      end
    end)
  end

  defp remove_holder(state, holder, keys) do
    leases =
      Enum.reduce(keys, state.leases, fn key, leases ->
        remaining = leases |> Map.get(key, MapSet.new()) |> MapSet.delete(holder)

        if MapSet.size(remaining) == 0 do
          Map.delete(leases, key)
        else
          Map.put(leases, key, remaining)
        end
      end)

    %{state | holders: Map.delete(state.holders, holder), leases: leases}
  end
end
