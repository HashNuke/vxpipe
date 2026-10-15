defmodule Vxpipe.Gateway.Session do
  @moduledoc false

  use GenServer

  alias Vxpipe.Gateway.{CallCleanup, CallCleanupSupervisor}
  alias Vxpipe.Gateway.Session.Snapshot

  @claim_timeout 5_000

  def start_link(options) do
    session_id = Keyword.fetch!(options, :session_id)
    GenServer.start_link(__MODULE__, options, name: via(session_id))
  end

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :session_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def claim(session_id) do
    case Registry.lookup(Vxpipe.Gateway.SessionRegistry, session_id) do
      [{session, _value}] -> GenServer.call(session, :claim, @claim_timeout)
      [] -> {:error, :not_found}
    end
  catch
    :exit, _reason -> {:error, :not_found}
  end

  def bind_connection(session_id, connection) when is_pid(connection) do
    case Registry.lookup(Vxpipe.Gateway.SessionRegistry, session_id) do
      [{session, _value}] ->
        GenServer.call(session, {:bind_connection, connection}, @claim_timeout)

      [] ->
        {:error, :not_found}
    end
  catch
    :exit, _reason -> {:error, :not_found}
  end

  def abandon(session_id) do
    case Registry.lookup(Vxpipe.Gateway.SessionRegistry, session_id) do
      [{session, _value}] -> GenServer.cast(session, {:abandon, self()})
      [] -> :ok
    end
  end

  def snapshot(session) do
    GenServer.call(session, :snapshot, @claim_timeout)
  end

  @impl true
  def init(options) do
    ttl_ms = Keyword.fetch!(options, :ttl_ms)
    now = DateTime.utc_now(:millisecond)
    expires_at = DateTime.add(now, ttl_ms, :millisecond)
    expires_after = System.monotonic_time(:millisecond) + ttl_ms
    _timer = Process.send_after(self(), :expire, ttl_ms)

    release = Keyword.get(options, :release_admission)
    cleanup_binding = Keyword.get(options, :cleanup_binding)

    snapshot = %Snapshot{
      session_id: Keyword.fetch!(options, :session_id),
      tenant_id: Keyword.fetch!(options, :tenant_id),
      actor_id: Keyword.fetch!(options, :actor_id),
      room_id: Keyword.fetch!(options, :room_id),
      incarnation_id: Keyword.fetch!(options, :incarnation_id),
      participant_id: Keyword.fetch!(options, :participant_id),
      tool_visibility: Keyword.fetch!(options, :tool_visibility),
      expires_at: expires_at,
      admission_owner: if(is_function(release, 0) or not is_nil(cleanup_binding), do: self()),
      cleanup_binding: cleanup_binding
    }

    state = %{
      expires_after: expires_after,
      snapshot: snapshot,
      state: :pending,
      release_admission: release,
      admission_released?: false,
      cleanup_tracker: nil,
      cleanup_monitor: nil,
      claimant: nil,
      claimant_monitor: nil,
      connection_monitor: nil,
      room_monitor: nil
    }

    case register_cleanup(state) do
      {:ok, registered} -> monitor_room(registered)
      {:error, _reason} -> failed_start(state)
    end
  end

  @impl true
  def handle_call(:snapshot, _from, %{state: :closing} = state),
    do: {:reply, {:error, :room_unavailable}, state}

  def handle_call(:snapshot, _from, state), do: {:reply, state.snapshot, state}

  def handle_call(:claim, {claimant, _tag}, state) do
    cond do
      state.state != :pending ->
        {:reply, {:error, :already_claimed}, state}

      System.monotonic_time(:millisecond) >= state.expires_after ->
        send(self(), :release_admission)
        {:reply, {:error, :expired}, %{state | state: :closing}}

      true ->
        monitor = if state.snapshot.admission_owner, do: Process.monitor(claimant)

        {:reply, {:ok, state.snapshot},
         %{state | state: :claimed, claimant: claimant, claimant_monitor: monitor}}
    end
  end

  def handle_call(
        {:bind_connection, connection},
        {claimant, _tag},
        %{state: :claimed, claimant: claimant, connection_monitor: nil} = state
      ) do
    if state.claimant_monitor, do: Process.demonitor(state.claimant_monitor, [:flush])
    monitor = if state.snapshot.admission_owner, do: Process.monitor(connection)
    {:reply, :ok, %{state | claimant_monitor: nil, connection_monitor: monitor}}
  end

  def handle_call({:bind_connection, _connection}, _from, state),
    do: {:reply, {:error, :invalid_claimant}, state}

  @impl true
  def handle_cast({:abandon, claimant}, %{claimant: claimant, connection_monitor: nil} = state),
    do: release_later(state)

  def handle_cast({:abandon, _claimant}, state), do: {:noreply, state}

  @impl true
  def handle_info(:expire, %{connection_monitor: monitor} = state) when is_reference(monitor),
    do: {:noreply, state}

  def handle_info(:expire, state), do: release_later(state)

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{cleanup_monitor: monitor} = state),
    do: release_later(%{state | cleanup_tracker: nil, cleanup_monitor: nil})

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state)
      when monitor == state.claimant_monitor or monitor == state.connection_monitor or
             monitor == state.room_monitor,
      do: release_later(state)

  def handle_info(:release_admission, state) do
    released? = state.admission_released? or release_admission(state.release_admission) == :ok
    state = %{state | admission_released?: released?}

    if released? and acknowledge_cleanup(state.cleanup_tracker) == :ok do
      {:stop, :normal, state}
    else
      Process.send_after(self(), :release_admission, 1_000)
      {:noreply, state}
    end
  end

  def handle_info(_stale, state), do: {:noreply, state}

  @impl true
  def format_status(status),
    do: %{status | state: Map.take(status.state, [:state, :expires_after])}

  defp register_cleanup(state) do
    case Snapshot.cleanup_binding(state.snapshot) do
      {:ok, nil} ->
        {:ok, state}

      {:ok, binding} ->
        with {:ok, tracker} <- CallCleanupSupervisor.lookup(binding),
             :ok <- CallCleanup.register(tracker, :session, self()) do
          {:ok, %{state | cleanup_tracker: tracker, cleanup_monitor: Process.monitor(tracker)}}
        end

      {:error, _reason} = error ->
        error
    end
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  defp monitor_room(state) do
    snapshot = state.snapshot

    case Vxpipe.CallEngine.monitor_room(
           snapshot.tenant_id,
           snapshot.room_id,
           snapshot.incarnation_id
         ) do
      {:ok, monitor} -> {:ok, %{state | room_monitor: monitor}}
      {:error, :room_unavailable} -> failed_start(state)
    end
  end

  defp failed_start(state) do
    if state.snapshot.admission_owner do
      send(self(), :release_admission)
      {:ok, %{state | state: :closing}}
    else
      {:stop, :room_unavailable}
    end
  end

  defp acknowledge_cleanup(nil), do: :ok

  defp acknowledge_cleanup(tracker) do
    CallCleanup.acknowledge(tracker, self(), :complete)
  catch
    :exit, _reason -> {:error, :cleanup_unavailable}
  end

  defp release_later(state) do
    send(self(), :release_admission)
    {:noreply, %{state | state: :closing}}
  end

  defp release_admission(nil), do: :ok

  defp release_admission(release) do
    release.()
  rescue
    _error -> {:error, :unavailable}
  catch
    _kind, _reason -> {:error, :unavailable}
  end

  defp via(session_id) do
    {:via, Registry, {Vxpipe.Gateway.SessionRegistry, session_id}}
  end
end
