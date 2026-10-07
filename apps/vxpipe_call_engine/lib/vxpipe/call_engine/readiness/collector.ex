defmodule Vxpipe.CallEngine.Readiness.Collector do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Readiness.{Barrier, Probe, Report, Resource, Watch}

  @call_timeout 1_000
  @maximum_resources 256
  @task_supervisor Vxpipe.CallEngine.ReadinessTaskSupervisor

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, Keyword.fetch!(options, :attempt_id)},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary
    }
  end

  def snapshot(collector), do: GenServer.call(collector, :snapshot, @call_timeout)

  def refresh(collector), do: GenServer.call(collector, :refresh, @call_timeout)

  def reconcile(collector, attempt_id, resources) do
    GenServer.call(collector, {:reconcile, attempt_id, resources}, @call_timeout)
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    resources = Keyword.fetch!(options, :resources)

    if length(resources) <= @maximum_resources do
      owner = Keyword.fetch!(options, :owner)
      clock = Keyword.get(options, :clock, fn -> System.monotonic_time(:millisecond) end)
      deadline_ms = Keyword.fetch!(options, :deadline_ms)
      deadline_id = make_ref()
      delay = max(deadline_ms - clock.(), 0)
      deadline_timer = Process.send_after(self(), {:readiness_deadline, deadline_id}, delay)

      state = %{
        owner: owner,
        clock: clock,
        owner_monitor: Process.monitor(owner),
        barrier:
          Barrier.new(
            Keyword.fetch!(options, :incarnation_id),
            Keyword.fetch!(options, :attempt_id),
            resources
          ),
        deadline_ms: deadline_ms,
        deadline_id: deadline_id,
        deadline_timer: deadline_timer,
        expired?: false,
        failure: nil,
        monitors: %{},
        watched: MapSet.new(),
        worker: nil,
        batch_id: nil,
        reprobe?: false,
        poll: nil,
        poll_interval_ms: Keyword.get(options, :poll_interval_ms, 100),
        maximum_concurrency: Keyword.get(options, :maximum_concurrency, 8),
        probe_timeout_ms: Keyword.get(options, :probe_timeout_ms, 5_500),
        last_snapshot: nil
      }

      {:ok, state |> monitor_resources(resources) |> publish(), {:continue, :probe}}
    else
      {:stop, :too_many_readiness_resources}
    end
  end

  @impl true
  def handle_continue(:probe, state), do: {:noreply, start_batch(state)}

  @impl true
  def handle_call(:snapshot, _from, state) do
    state = if expired?(state), do: expire(state), else: state
    {:reply, projection(state), state}
  end

  def handle_call(:refresh, _from, state) do
    if expired?(state) do
      {:reply, {:error, :deadline_elapsed}, expire(state)}
    else
      state = cancel_batch(state)

      state =
        Enum.reduce(state.barrier.entries, state, fn {_key, entry}, state ->
          put_status(state, entry.resource, :preparing)
        end)

      {:reply, :ok, publish(state), {:continue, :probe}}
    end
  end

  def handle_call({:reconcile, attempt_id, resources}, _from, state) do
    cond do
      expired?(state) ->
        {:reply, {:error, :deadline_elapsed}, expire(state)}

      length(resources) > @maximum_resources ->
        {:reply, {:error, :too_many_readiness_resources}, state}

      true ->
        state = cancel_batch(state)
        {barrier, diff} = Barrier.reconcile(state.barrier, attempt_id, resources)
        state = %{state | barrier: barrier, failure: nil}
        state = state |> monitor_resources(resources) |> publish()
        {:reply, {:ok, diff}, state, {:continue, :probe}}
    end
  end

  @impl true
  def handle_info(
        {:vxpipe_readiness_probe, batch_id, resource, result},
        %{batch_id: batch_id} = state
      )
      when is_reference(batch_id) do
    state = if expired?(state), do: expire(state), else: accept_result(state, resource, result)

    {:noreply, publish(state)}
  end

  def handle_info({ref, :ok}, %{worker: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | worker: nil, batch_id: nil}

    if state.reprobe?,
      do: {:noreply, start_batch(%{state | reprobe?: false})},
      else: {:noreply, schedule_poll(state)}
  end

  def handle_info({:vxpipe_readiness_resource_changed, instance}, state) do
    cond do
      not MapSet.member?(state.watched, instance) -> {:noreply, state}
      state.worker != nil -> {:noreply, %{state | reprobe?: true}}
      true -> {:noreply, state |> cancel_poll() |> start_batch()}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{owner_monitor: monitor} = state) do
    {:stop, :normal, cancel_batch(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{worker: %Task{ref: ref}} = state) do
    state = %{state | worker: nil, batch_id: nil, failure: :resource_unavailable}
    {:noreply, state |> fail_pending() |> publish()}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {:noreply, state}

      {resource, monitors} ->
        state = %{state | monitors: monitors, failure: :resource_unavailable}
        {:noreply, state |> put_status(resource, :failed) |> publish()}
    end
  end

  def handle_info({:readiness_poll, id}, %{poll: {id, _timer}} = state) do
    {:noreply, start_batch(%{state | poll: nil})}
  end

  def handle_info({:readiness_deadline, id}, %{deadline_id: id} = state) do
    {:noreply, expire(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = cancel_batch(state)
    _ = Process.cancel_timer(state.deadline_timer)
    :ok
  end

  defp start_batch(state) do
    resources =
      for {_key, %{resource: resource, status: :preparing}} <- state.barrier.entries,
          Resource.bound?(resource),
          do: resource

    cond do
      expired?(state) ->
        expire(state)

      resources == [] or Barrier.status(state.barrier) == :failed ->
        state

      true ->
        collector = self()
        batch_id = make_ref()

        options = [
          maximum_concurrency: state.maximum_concurrency,
          timeout: max(min(state.probe_timeout_ms, state.deadline_ms - state.clock.()), 0)
        ]

        worker =
          Task.Supervisor.async_nolink(@task_supervisor, fn ->
            Probe.run(resources, collector, batch_id, options)
          end)

        %{state | worker: worker, batch_id: batch_id}
    end
  end

  defp accept_result(state, resource, {:ok, {:ok, resource, status}})
       when status in [:preparing, :ready, :failed] do
    put_status(state, resource, status)
  end

  defp accept_result(state, resource, {:ok, {:ok, %Resource{}, _status}}) do
    %{put_status(state, resource, :failed) | failure: :binding_changed}
  end

  defp accept_result(state, resource, {:ok, {:error, :unavailable}}),
    do: put_status(state, resource, :preparing)

  defp accept_result(state, resource, {:exit, :timeout}),
    do: put_status(state, resource, :preparing)

  defp accept_result(state, resource, _invalid) do
    %{put_status(state, resource, :failed) | failure: :resource_unavailable}
  end

  defp schedule_poll(%{poll_interval_ms: :manual} = state), do: state

  defp schedule_poll(state) do
    if Barrier.status(state.barrier) == :preparing and not expired?(state) do
      id = make_ref()
      timer = Process.send_after(self(), {:readiness_poll, id}, state.poll_interval_ms)
      %{state | poll: {id, timer}}
    else
      state
    end
  end

  defp put_status(state, resource, status) do
    key = Resource.key(resource)

    case Map.get(state.barrier.entries, key) do
      %{resource: ^resource} = entry ->
        report = %Report{
          incarnation_id: state.barrier.incarnation_id,
          attempt_id: state.barrier.attempt_id,
          request_id: entry.request_id,
          resource: resource,
          status: status,
          sequence: entry.sequence + 1
        }

        {_outcome, barrier} = Barrier.report(state.barrier, report)
        %{state | barrier: barrier}

      _stale ->
        state
    end
  end

  defp fail_pending(state) do
    Enum.reduce(state.barrier.entries, state, fn {_key, entry}, state ->
      if entry.status == :preparing,
        do: put_status(state, entry.resource, :failed),
        else: state
    end)
  end

  defp monitor_resources(state, resources) do
    desired = MapSet.new(Enum.filter(resources, &is_pid(&1.instance)))

    retained =
      Map.filter(state.monitors, fn {ref, resource} ->
        if MapSet.member?(desired, resource) do
          true
        else
          Process.demonitor(ref, [:flush])
          false
        end
      end)

    new = MapSet.difference(desired, MapSet.new(Map.values(retained)))
    monitors = Enum.reduce(new, retained, &Map.put(&2, Process.monitor(&1.instance), &1))
    %{state | monitors: monitors} |> watch_instances()
  end

  defp cancel_batch(state) do
    if state.worker, do: Task.shutdown(state.worker, :brutal_kill)
    %{cancel_poll(state) | worker: nil, batch_id: nil, reprobe?: false}
  end

  defp cancel_poll(%{poll: nil} = state), do: state

  defp cancel_poll(%{poll: {_id, timer}} = state) do
    Process.cancel_timer(timer)
    %{state | poll: nil}
  end

  # Owners announce readiness changes through `Watch`; subscribe once per owning process.
  defp watch_instances(state) do
    instances = state.monitors |> Map.values() |> MapSet.new(& &1.instance)
    Enum.each(MapSet.difference(state.watched, instances), &Watch.unsubscribe/1)
    Enum.each(MapSet.difference(instances, state.watched), &Watch.subscribe/1)
    %{state | watched: instances}
  end

  defp expired?(state),
    do: state.expired? or state.clock.() >= state.deadline_ms

  defp expire(state) do
    state = cancel_batch(state)
    publish(%{state | expired?: true, failure: :deadline_elapsed})
  end

  defp projection(state) do
    %{
      incarnation_id: state.barrier.incarnation_id,
      attempt_id: state.barrier.attempt_id,
      status: if(state.expired?, do: :failed, else: Barrier.status(state.barrier)),
      failure: state.failure,
      blockers: Barrier.blockers(state.barrier)
    }
  end

  defp publish(state) do
    snapshot = projection(state)

    if snapshot != state.last_snapshot do
      send(state.owner, {:vxpipe_readiness_changed, self(), snapshot})
    end

    %{state | last_snapshot: snapshot}
  end
end
