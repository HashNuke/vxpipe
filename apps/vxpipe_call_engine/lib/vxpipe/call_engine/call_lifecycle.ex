defmodule Vxpipe.CallEngine.CallLifecycle do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.CallLifecycle.ProcessTimer
  alias Vxpipe.CallEngine.ResolvedCallPlan

  @call_timeout 1_000

  def start_link(options) do
    incarnation_id = Keyword.fetch!(options, :incarnation_id)
    GenServer.start_link(__MODULE__, options, name: via(incarnation_id))
  end

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      significant: true
    }
  end

  @spec bind(String.t(), pid()) :: {:ok, pid()} | {:error, :unavailable}
  def bind(incarnation_id, authority) when is_binary(incarnation_id) and is_pid(authority) do
    lifecycle = via(incarnation_id)

    case safe_call(lifecycle, {:bind, authority}) do
      {:ok, pid} when is_pid(pid) -> {:ok, pid}
      _unavailable -> {:error, :unavailable}
    end
  end

  @spec ready(pid()) :: :ok | {:error, :unavailable}
  def ready(lifecycle) when is_pid(lifecycle) do
    case safe_call(lifecycle, :ready) do
      :ok -> :ok
      _unavailable -> {:error, :unavailable}
    end
  end

  @spec startup_failed(String.t(), atom()) ::
          :ok | {:ignored, :expired | :failed | :ready} | {:error, :unavailable}
  def startup_failed(incarnation_id, reason)
      when is_binary(incarnation_id) and is_atom(reason) do
    case safe_call(via(incarnation_id), {:startup_failed, reason}) do
      :ok -> :ok
      {:ignored, status} when status in [:expired, :failed, :ready] -> {:ignored, status}
      _unavailable -> {:error, :unavailable}
    end
  end

  @impl true
  def init(options) do
    with %ResolvedCallPlan{} = plan <- Keyword.get(options, :plan),
         settings when is_list(settings) <- Keyword.get(options, :call_lifecycle),
         readiness_timeout_ms
         when is_integer(readiness_timeout_ms) and
                readiness_timeout_ms > 0 <-
           Keyword.get(settings, :readiness_timeout_ms),
         {timer_module, timer_options} <- Keyword.get(settings, :timer, {ProcessTimer, []}),
         true <- timer?(timer_module, timer_options) do
      state = %{
        authority: nil,
        readiness: :pending,
        timer: {timer_module, timer_options},
        timers: %{},
        unbound_events: []
      }

      state = schedule(state, :max_duration, plan.max_duration_ms)
      {:ok, schedule(state, :readiness, readiness_timeout_ms)}
    else
      _invalid -> {:stop, :invalid_configuration}
    end
  end

  @impl true
  def handle_call({:bind, authority}, _from, %{authority: nil} = state) do
    Enum.each(Enum.reverse(state.unbound_events), &notify(authority, &1))
    {:reply, {:ok, self()}, %{state | authority: authority, unbound_events: []}}
  end

  def handle_call({:bind, authority}, _from, %{authority: authority} = state) do
    {:reply, {:ok, self()}, state}
  end

  def handle_call({:bind, _authority}, _from, state) do
    {:reply, {:error, :already_bound}, state}
  end

  def handle_call(:ready, _from, %{readiness: :pending} = state) do
    {:reply, :ok, state |> cancel(:readiness) |> Map.put(:readiness, :ready)}
  end

  def handle_call(:ready, _from, state), do: {:reply, :ok, state}

  def handle_call({:startup_failed, reason}, _from, %{readiness: :pending} = state) do
    state =
      state
      |> cancel(:readiness)
      |> Map.put(:readiness, :failed)
      |> deliver({:startup_failure, reason})

    {:reply, :ok, state}
  end

  def handle_call({:startup_failed, _reason}, _from, state) do
    {:reply, {:ignored, state.readiness}, state}
  end

  @impl true
  def handle_info({:vxpipe_call_lifecycle_timer, token, event}, state) do
    case Map.get(state.timers, event) do
      %{token: ^token} -> {:noreply, fire(event, state)}
      _missing_or_stale -> {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.timers, fn {_event, timer} -> cancel_timer(timer, state.timer) end)
    :ok
  end

  defp schedule(state, event, timeout_ms) do
    token = make_ref()
    {timer_module, timer_options} = state.timer
    handle = timer_module.schedule(self(), token, event, timeout_ms, timer_options)
    timer = %{handle: handle, token: token}
    %{state | timers: Map.put(state.timers, event, timer)}
  end

  defp cancel(state, event) do
    case Map.pop(state.timers, event) do
      {nil, _timers} ->
        state

      {timer, timers} ->
        cancel_timer(timer, state.timer)
        %{state | timers: timers}
    end
  end

  defp cancel_timer(timer, {timer_module, timer_options}) do
    timer_module.cancel(timer.handle, timer_options)
  end

  defp fire(:readiness, state) do
    state
    |> Map.put(:readiness, :expired)
    |> remove_timer(:readiness)
    |> deliver(:readiness)
  end

  defp fire(event, state), do: state |> remove_timer(event) |> deliver(event)

  defp deliver(state, event) do
    if is_pid(state.authority) do
      notify(state.authority, event)
      state
    else
      %{state | unbound_events: [event | state.unbound_events]}
    end
  end

  defp remove_timer(state, event), do: %{state | timers: Map.delete(state.timers, event)}

  defp notify(authority, event), do: send(authority, {:vxpipe_call_lifecycle, self(), event})

  defp timer?(timer_module, timer_options) do
    is_atom(timer_module) and is_list(timer_options) and Code.ensure_loaded?(timer_module) and
      function_exported?(timer_module, :schedule, 5) and
      function_exported?(timer_module, :cancel, 2)
  end

  defp safe_call(server, request) do
    GenServer.call(server, request, @call_timeout)
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp via(incarnation_id) do
    {:via, Registry, {Vxpipe.CallEngine.RoomRegistry, {:call_lifecycle, incarnation_id}}}
  end
end
