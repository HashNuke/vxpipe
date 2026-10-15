defmodule Vxpipe.Gateway.CallCleanup do
  @moduledoc """
  Retains exact-incarnation cleanup evidence independently of request lifetimes.

  Registration tracks whole resource supervision roots and their original semantic
  acknowledgement owners. Orderly process termination alone cannot confirm remote
  carrier cleanup or durable usage. Lost membership must remain unknown to callers;
  this temporary child is never automatically restarted with an empty resource set.
  """

  use GenServer, restart: :temporary

  alias Vxpipe.CallEngine

  @resource_kinds [
    :session,
    :web_rtc,
    :telephony_media,
    :telephony_socket,
    :incoming_leg,
    :outgoing_leg
  ]

  def start_link({binding, _initial_resource} = options) do
    GenServer.start_link(__MODULE__, options, name: name(binding))
  end

  @doc false
  def name(binding) do
    identity = Map.take(binding, [:tenant_key, :call_id, :room_id, :incarnation_id])
    {:via, Registry, {Vxpipe.Gateway.CallCleanupRegistry, identity}}
  end

  def register(tracker, kind, resource) when kind in @resource_kinds and is_pid(resource),
    do: GenServer.call(tracker, {:register, kind, resource})

  def seal(tracker), do: GenServer.call(tracker, :seal)

  def acknowledge(tracker, resource, outcome) when outcome in [:complete, :unknown],
    do: GenServer.call(tracker, {:acknowledge, resource, outcome})

  def snapshot(tracker), do: GenServer.call(tracker, :snapshot)
  def observe(tracker), do: GenServer.call(tracker, :observe)

  @impl true
  def init(
        {%{tenant_key: tenant, call_id: call, room_id: room, incarnation_id: incarnation} =
           binding, initial_resource}
      )
      when is_binary(tenant) and is_binary(call) and is_binary(room) and is_binary(incarnation) do
    case CallEngine.monitor_room_completion(tenant, room, incarnation) do
      {:ok, monitor} ->
        state = %{
          binding: Map.take(binding, [:tenant_key, :call_id, :room_id, :incarnation_id]),
          sealed?: false,
          engine_outcome: :pending,
          resources: %{},
          monitors: %{monitor => :engine},
          observers: %{},
          completed_at: nil
        }

        {:ok, seed_resource(state, initial_resource)}

      {:error, :room_unavailable} ->
        {:stop, :room_unavailable}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, project(state), state}

  def handle_call(:observe, {observer, _}, state) do
    state = add_observer(state, observer)
    {:reply, {:ok, project(state)}, state}
  end

  def handle_call(:seal, _from, state), do: reply(:ok, state, %{state | sealed?: true})

  def handle_call({:register, kind, root}, {owner, _}, state) do
    case Map.fetch(state.resources, root) do
      {:ok, %{kind: ^kind, owner: ^owner}} -> {:reply, :ok, state}
      {:ok, _} -> {:reply, {:error, :invalid_owner}, state}
      :error when state.sealed? -> {:reply, {:error, :sealed}, state}
      :error -> reply(:ok, state, add_resource(state, kind, root, owner))
    end
  end

  def handle_call({:acknowledge, root, outcome}, {owner, _}, state) do
    case Map.fetch(state.resources, root) do
      {:ok, %{owner: ^owner, owner_alive?: true} = resource} ->
        if state.completed_at && outcome != :complete do
          {:reply, {:error, :completed}, state}
        else
          resources = Map.put(state.resources, root, %{resource | acknowledgement: outcome})
          reply(:ok, state, %{state | resources: resources})
        end

      _ ->
        {:reply, {:error, :invalid_owner}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, reason}, state) do
    {target, monitors} = Map.pop(state.monitors, monitor)
    updated = record_down(%{state | monitors: monitors}, target, reason)
    {:noreply, changed(state, updated)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp seed_resource(state, nil), do: state

  defp seed_resource(state, {kind, root, owner})
       when kind in @resource_kinds and is_pid(root) and is_pid(owner),
       do: add_resource(state, kind, root, owner)

  defp add_resource(state, kind, root, owner) do
    resource = %{
      kind: kind,
      root: root,
      owner: owner,
      owner_alive?: true,
      root_outcome: :pending,
      acknowledgement: :pending
    }

    monitors = Map.put(state.monitors, Process.monitor(root), {:resource, root})

    monitors =
      if owner == root,
        do: monitors,
        else: Map.put(monitors, Process.monitor(owner), {:owner, root})

    %{state | resources: Map.put(state.resources, root, resource), monitors: monitors}
  end

  defp add_observer(state, observer) do
    if Map.has_key?(state.observers, observer) do
      state
    else
      monitor = Process.monitor(observer)

      %{
        state
        | observers: Map.put(state.observers, observer, monitor),
          monitors: Map.put(state.monitors, monitor, {:observer, observer})
      }
    end
  end

  defp record_down(state, :engine, reason),
    do: %{state | engine_outcome: exit_outcome(reason), sealed?: true}

  defp record_down(state, {:resource, root}, reason) do
    resources =
      Map.update!(state.resources, root, fn resource ->
        %{
          resource
          | root_outcome: exit_outcome(reason),
            owner_alive?: resource.owner_alive? and resource.owner != root
        }
      end)

    %{state | resources: resources}
  end

  defp record_down(state, {:owner, root}, _reason) do
    resources = Map.update!(state.resources, root, &%{&1 | owner_alive?: false})
    %{state | resources: resources}
  end

  defp record_down(state, {:observer, observer}, _reason),
    do: %{state | observers: Map.delete(state.observers, observer)}

  defp record_down(state, nil, _reason), do: state

  defp exit_outcome(:normal), do: :complete
  defp exit_outcome(:shutdown), do: :complete
  defp exit_outcome({:shutdown, _}), do: :complete
  defp exit_outcome(_), do: :unknown

  defp reply(result, previous, updated), do: {:reply, result, changed(previous, updated)}

  defp changed(previous, updated) do
    updated =
      if is_nil(updated.completed_at) and status(updated) == :complete,
        do: %{updated | completed_at: DateTime.utc_now()},
        else: updated

    snapshot = project(updated)

    if snapshot != project(previous) do
      Enum.each(updated.observers, fn {pid, _} ->
        send(pid, {:call_cleanup_changed, self(), snapshot})
      end)
    end

    updated
  end

  defp project(state) do
    state
    |> Map.take([:binding, :sealed?, :engine_outcome, :resources, :completed_at])
    |> Map.put(:status, status(state))
  end

  defp status(%{sealed?: false}), do: :open

  defp status(state) do
    outcomes = [
      state.engine_outcome | Enum.map(state.resources, fn {_, r} -> resource_outcome(r) end)
    ]

    cond do
      :unknown in outcomes -> :unknown
      Enum.all?(outcomes, &(&1 == :complete)) -> :complete
      true -> :pending
    end
  end

  defp resource_outcome(resource) do
    cond do
      resource.root_outcome == :unknown -> :unknown
      resource.acknowledgement == :unknown -> :unknown
      not resource.owner_alive? and resource.acknowledgement != :complete -> :unknown
      resource.root_outcome == :complete and resource.acknowledgement == :complete -> :complete
      true -> :pending
    end
  end
end
