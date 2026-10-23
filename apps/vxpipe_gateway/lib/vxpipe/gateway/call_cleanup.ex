defmodule Vxpipe.Gateway.CallCleanup do
  @moduledoc """
  Retains exact-incarnation cleanup evidence independently of request lifetimes.

  Registration tracks whole resource supervision roots and their original semantic
  acknowledgement owners. Orderly process termination alone cannot confirm remote
  carrier cleanup or durable usage. Lost membership must remain unknown to callers;
  this temporary child is never automatically restarted with an empty resource set.
  """

  use GenServer, restart: :temporary

  alias Vxpipe.{CallEngine, Calls}

  @task_supervisor Vxpipe.Gateway.AdmissionTaskSupervisor

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

  def start_link({binding, _initial_resource, _completion_options} = options) do
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

  def snapshot(tracker, timeout \\ 5_000), do: GenServer.call(tracker, :snapshot, timeout)
  def observe(tracker), do: GenServer.call(tracker, :observe)

  @impl true
  def init({binding, initial_resource}), do: init({binding, initial_resource, []})

  def init(
        {%{tenant_key: tenant, call_id: call, room_id: room, incarnation_id: incarnation} =
           binding, initial_resource, options}
      )
      when is_binary(tenant) and is_binary(call) and is_binary(room) and is_binary(incarnation) do
    with {:ok, completion} <- completion_options(options),
         {:ok, monitor} <- CallEngine.monitor_room_completion(tenant, room, incarnation) do
      state = %{
        binding: Map.take(binding, [:tenant_key, :call_id, :room_id, :incarnation_id]),
        sealed?: false,
        engine_outcome: :pending,
        resources: %{},
        monitors: %{monitor => :engine},
        observers: %{},
        completed_at: nil,
        completion: completion,
        completion_task: nil,
        completion_result: nil,
        completion_retry: nil
      }

      {:ok, seed_resource(state, initial_resource)}
    else
      {:error, reason} -> {:stop, reason}
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
  def handle_info({ref, result}, %{completion_task: %Task{ref: ref}} = state),
    do: {:noreply, %{state | completion_result: result == :ok}}

  def handle_info(
        {:DOWN, ref, :process, worker, reason},
        %{completion_task: %Task{ref: ref, pid: worker}} = state
      ) do
    persisted? = state.completion_result == true and reason == :normal
    state = %{state | completion_task: nil, completion_result: nil}

    if persisted?,
      do: {:stop, :normal, state},
      else: {:noreply, retry_completion(state)}
  end

  def handle_info({:retry_completion, token}, %{completion_retry: token} = state),
    do: {:noreply, persist_completion(%{state | completion_retry: nil})}

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

    persist_completion(updated)
  end

  defp persist_completion(%{completion: nil} = state), do: state
  defp persist_completion(%{completed_at: nil} = state), do: state
  defp persist_completion(%{completion_task: %Task{}} = state), do: state
  defp persist_completion(%{completion_retry: token} = state) when not is_nil(token), do: state

  defp persist_completion(state) do
    binding = state.binding
    completed_at = state.completed_at
    options = state.completion

    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        # The deadline belongs to the worker before storage starts, so even loss
        # of the tracker cannot leave a blocked completion operation unbounded.
        {:ok, timer} = :timer.kill_after(options.timeout_ms, self())

        try do
          case Calls.complete_call_cleanup(binding, completed_at, options.calls_options) do
            {:ok, _validated_call} -> :ok
            _error -> :error
          end
        after
          :timer.cancel(timer)
        end
      end)

    %{state | completion_task: task, completion_result: nil}
  catch
    :exit, _ -> retry_completion(state)
  end

  defp retry_completion(state) do
    token = make_ref()
    delay = state.completion.retry_ms
    Process.send_after(self(), {:retry_completion, token}, delay)
    completion = %{state.completion | retry_ms: min(max(delay * 2, 1), 5_000)}
    %{state | completion_retry: token, completion: completion}
  end

  defp completion_options(options) when is_list(options) do
    if Keyword.keyword?(options) and Keyword.keys(options) -- [:completion] == [] do
      case Keyword.fetch(options, :completion) do
        :error -> {:ok, nil}
        {:ok, completion} -> validate_completion(completion)
      end
    else
      {:error, :invalid_completion_options}
    end
  end

  defp completion_options(_options), do: {:error, :invalid_completion_options}

  defp validate_completion(options) when is_list(options) do
    if Keyword.keyword?(options) do
      completion = %{
        calls_options: Keyword.get(options, :calls_options, []),
        timeout_ms: Keyword.get(options, :timeout_ms, 5_000),
        retry_ms: Keyword.get(options, :retry_ms, 250)
      }

      if is_list(completion.calls_options) and Keyword.keyword?(completion.calls_options) and
           is_integer(completion.timeout_ms) and completion.timeout_ms in 1..30_000 and
           is_integer(completion.retry_ms) and completion.retry_ms in 0..5_000 and
           Keyword.keys(options) -- [:calls_options, :timeout_ms, :retry_ms] == [],
         do: {:ok, completion},
         else: {:error, :invalid_completion_options}
    else
      {:error, :invalid_completion_options}
    end
  end

  defp validate_completion(_options), do: {:error, :invalid_completion_options}

  defp project(state) do
    state
    |> Map.take([:binding, :sealed?, :engine_outcome, :resources, :completed_at])
    |> Map.put(:status, status(state))
    |> Map.put(:uncertain?, uncertain?(state))
  end

  defp status(%{sealed?: false}), do: :open

  defp status(state) do
    outcomes = outcomes(state)

    cond do
      :unknown in outcomes -> :unknown
      Enum.all?(outcomes, &(&1 == :complete)) -> :complete
      true -> :pending
    end
  end

  defp uncertain?(state), do: :unknown in outcomes(state)

  defp outcomes(state),
    do: [state.engine_outcome | Enum.map(state.resources, fn {_, r} -> resource_outcome(r) end)]

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
