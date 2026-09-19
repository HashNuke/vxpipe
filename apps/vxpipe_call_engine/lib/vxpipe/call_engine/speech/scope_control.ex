defmodule Vxpipe.CallEngine.Speech.ScopeControl do
  @moduledoc false
  use GenServer

  alias Vxpipe.CallEngine.Speech.{Allocation, Channel, ProviderName, SessionTree}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def reserve(allocation, options, timeout),
    do: GenServer.call(allocation.scope.control, {:reserve, allocation, options}, timeout)

  def claim(allocation),
    do: GenServer.call(allocation.scope.control, {:claim, allocation}, remaining(allocation))

  def bind(allocation, tree),
    do: GenServer.call(allocation.scope.control, {:bind, allocation, tree}, remaining(allocation))

  def close(allocation, reason),
    do: GenServer.call(allocation.scope.control, {:close, allocation, reason}, 5_000)

  def failed(allocation, reason),
    do: GenServer.cast(allocation.scope.control, {:failed, allocation, reason})

  def activate(allocation, authority, consumer),
    do:
      GenServer.call(
        allocation.scope.control,
        {:activate, allocation, authority, consumer},
        remaining(allocation)
      )

  @impl true
  def init(options),
    do: {:ok, %{owner: Process.monitor(Keyword.fetch!(options, :owner)), entries: %{}}}

  @impl true
  def handle_call({:reserve, allocation, options}, _from, state) do
    cond do
      not valid_owner?(allocation) -> {:reply, {:error, :closed}, state}
      map_size(state.entries) >= 2 -> {:reply, {:error, :busy}, state}
      true -> reserve_entry(allocation, options, state)
    end
  end

  def handle_call({:claim, allocation}, _from, state) do
    case Map.get(state.entries, allocation.generation) do
      %{private: private} = entry when not is_nil(private) ->
        if valid_owner?(allocation) do
          {:reply, {:ok, private}, put_entry(state, allocation, %{entry | private: nil})}
        else
          {:reply, {:error, :closed}, retire(state, allocation, :startup_timeout)}
        end

      _missing ->
        {:reply, {:error, :closed}, state}
    end
  end

  def handle_call({:bind, allocation, tree}, _from, state) do
    case Map.get(state.entries, allocation.generation) do
      nil ->
        {:reply, {:error, :closed}, state}

      entry ->
        entry = %{entry | tree: tree, tree_monitor: Process.monitor(tree)}
        state = put_entry(state, allocation, entry)

        if valid_owner?(allocation) do
          {:reply, :ok, state}
        else
          {:reply, {:error, :closed}, retire(state, allocation, :closed)}
        end
    end
  end

  def handle_call({:close, allocation, reason}, {caller, _tag}, state) do
    case Map.get(state.entries, allocation.generation) do
      nil ->
        {:reply, :ok, state}

      entry ->
        if entry.allocation == allocation and
             caller in [entry.allocation.owner, entry.lease, entry.consumer] do
          {:reply, :ok, retire(state, entry.allocation, reason)}
        else
          {:reply, {:error, :not_owner}, state}
        end
    end
  end

  def handle_call({:activate, allocation, authority, consumer}, {channel, _tag}, state) do
    case Map.get(state.entries, allocation.generation) do
      %{phase: :pending, allocation: ^allocation} = entry ->
        if channel == GenServer.whereis(Channel.address(allocation)) and
             authority == (entry.lease || entry.consumer) and valid_owner?(allocation) and
             is_pid(consumer) and Process.alive?(consumer) and Allocation.activate(allocation) do
          Process.cancel_timer(entry.timer)
          if entry.lease_monitor, do: Process.demonitor(entry.lease_monitor, [:flush])

          entry = %{
            entry
            | phase: :active,
              lease: nil,
              lease_monitor: nil,
              consumer: consumer,
              consumer_monitor: Process.monitor(consumer)
          }

          {:reply, :ok, put_entry(state, allocation, entry)}
        else
          {:reply, {:error, :not_adoptable}, state}
        end

      _entry ->
        {:reply, {:error, :not_adoptable}, state}
    end
  end

  @impl true
  def handle_cast({:failed, allocation, reason}, state),
    do: {:noreply, retire(state, allocation, reason)}

  @impl true
  def handle_info({:expired, allocation}, state) do
    state =
      if Allocation.pending?(allocation),
        do: retire(state, allocation, :startup_timeout),
        else: state

    {:noreply, state}
  end

  def handle_info({:admitted, allocation, result}, state) do
    case Map.get(state.entries, allocation.generation) do
      nil ->
        {:noreply, state}

      entry ->
        state = put_entry(state, allocation, %{entry | admitting?: false})

        state =
          if result == :ok, do: state, else: retire(state, allocation, :initialization_failed)

        {:noreply, release_finished(state, allocation)}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{owner: monitor} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state.entries, state, fn {_generation, entry}, acc ->
        cond do
          entry.tree_monitor == monitor ->
            acc = retire(acc, entry.allocation, :session_failed)
            current = Map.fetch!(acc.entries, entry.allocation.generation)
            acc = put_entry(acc, entry.allocation, %{current | tree: nil})
            release_finished(acc, entry.allocation)

          entry.owner_monitor == monitor ->
            retire(acc, entry.allocation, :owner_lost)

          entry.consumer_monitor == monitor ->
            retire(acc, entry.allocation, :consumer_lost)

          entry.lease_monitor == monitor and Allocation.pending?(entry.allocation) ->
            retire(acc, entry.allocation, :lease_lost)

          true ->
            acc
        end
      end)

    {:noreply, state}
  end

  @impl true
  def format_status(status) do
    status
    |> Map.put(:state, :speech_scope)
    |> Map.put(:message, :redacted)
    |> Map.put(:reason, :redacted)
    |> Map.put(:log, [])
  end

  defp reserve_entry(allocation, options, state) do
    entry = %{
      allocation: allocation,
      phase: :pending,
      consumer: allocation.consumer,
      consumer_monitor: nil,
      lease: allocation.lease,
      private: Keyword.get(options, :private, []),
      owner_monitor: Process.monitor(allocation.owner),
      lease_monitor: if(is_pid(allocation.lease), do: Process.monitor(allocation.lease)),
      timer: Process.send_after(self(), {:expired, allocation}, remaining(allocation)),
      tree: nil,
      tree_monitor: nil,
      admitting?: true,
      notified?: false
    }

    public = Keyword.take(options, [:provider, :options, :call_timeout])
    control = self()

    {:ok, _task} =
      Task.Supervisor.start_child(allocation.scope.admissions, fn ->
        result = admit(allocation, public)
        send(control, {:admitted, allocation, result})
      end)

    {:reply, {:ok, allocation, :starting}, put_entry(state, allocation, entry)}
  end

  defp admit(allocation, public) do
    with {:ok, tree} <-
           DynamicSupervisor.start_child(
             allocation.scope.sessions,
             {SessionTree, {allocation, public}}
           ),
         :ok <- bind(allocation, tree),
         {:ok, _worker} <-
           Task.Supervisor.start_child(SessionTree.commands(allocation), fn ->
             SessionTree.initialize(allocation, public)
           end) do
      :ok
    else
      _error -> :error
    end
  catch
    :exit, _reason -> :error
  end

  defp retire(state, allocation, reason) do
    Allocation.cancel(allocation)

    case Map.get(state.entries, allocation.generation) do
      nil ->
        state

      entry ->
        Process.cancel_timer(entry.timer)

        if not entry.notified? and reason != :closed,
          do:
            send(
              entry.lease || entry.consumer,
              {:vxpipe_speech_closed, allocation, reason}
            )

        # The gate exposes the exact initializer before user init. Revocation is
        # checked again after registration, so a pre-bind child cannot escape.
        case ProviderName.whereis_name(allocation) do
          :undefined -> :ok
          pid -> Process.exit(pid, :kill)
        end

        GenServer.cast(Channel.address(allocation), :retire)
        put_entry(state, allocation, %{entry | private: nil, notified?: true})
    end
  end

  defp release_finished(state, allocation) do
    case Map.get(state.entries, allocation.generation) do
      %{tree: nil, admitting?: false} = entry ->
        Process.cancel_timer(entry.timer)
        Process.demonitor(entry.owner_monitor, [:flush])
        if entry.lease_monitor, do: Process.demonitor(entry.lease_monitor, [:flush])
        if entry.consumer_monitor, do: Process.demonitor(entry.consumer_monitor, [:flush])
        %{state | entries: Map.delete(state.entries, allocation.generation)}

      _entry ->
        state
    end
  end

  defp put_entry(state, allocation, entry),
    do: %{state | entries: Map.put(state.entries, allocation.generation, entry)}

  defp valid_owner?(allocation),
    do:
      Allocation.valid?(allocation) and Process.alive?(allocation.owner) and
        (is_nil(allocation.lease) or Process.alive?(allocation.lease))

  defp remaining(allocation),
    do: max(allocation.deadline - System.monotonic_time(:millisecond), 1)
end
