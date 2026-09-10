defmodule Vxpipe.CallEngine.RemoteMCP.CatalogRefresher do
  @moduledoc """
  Schedules bounded catalog refresh work and expires a stale published snapshot.

  Configuration retrieval and remote discovery run in a supervised task. This process owns only
  timing and the last normalized outcome; it never retains a fetched integration set.
  """

  use GenServer

  alias Vxpipe.CallEngine.RemoteMCP.{CatalogRefreshCycle, CatalogStore, IntegrationCatalog}
  alias Vxpipe.CallEngine.RemoteMCP.CatalogRefresher.{Options, State}

  @refresh_call_timeout_ms 35_000
  @status_call_timeout_ms 5_000

  @type outcome :: CatalogRefreshCycle.outcome() | {:error, :refresh_timeout}

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, Keyword.take(options, [:name]))
  end

  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @spec refresh(GenServer.server(), timeout()) :: outcome()
  def refresh(server \\ __MODULE__, timeout \\ @refresh_call_timeout_ms) do
    GenServer.call(server, :refresh, timeout)
  end

  @spec status(GenServer.server()) :: %{
          expired?: boolean(),
          last_outcome: :pending | outcome(),
          refreshing?: boolean()
        }
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status, @status_call_timeout_ms)
  end

  @spec check_staleness(GenServer.server()) :: :expired | :fresh
  def check_staleness(server \\ __MODULE__) do
    GenServer.call(server, :check_staleness, @status_call_timeout_ms)
  end

  @impl true
  def init(options) do
    with {:ok, settings} <- Options.new(options),
         {:ok, now_ms} <- current_time(settings.clock) do
      state =
        %State{
          catalog_store: settings.catalog_store,
          clock: settings.clock,
          expired?: false,
          expiry_generation: nil,
          expiry_timer: nil,
          last_outcome: :pending,
          last_success_at_ms: now_ms,
          refresh_interval_ms: settings.refresh_interval_ms,
          refresh_options: settings.refresh_options,
          refresh_timeout_ms: settings.refresh_timeout_ms,
          refresh_timer: nil,
          source: settings.source,
          stale_after_ms: settings.stale_after_ms,
          task: nil,
          task_supervisor: settings.task_supervisor,
          task_timeout_timer: nil,
          waiters: []
        }
        |> schedule_expiry(settings.stale_after_ms)

      {:ok, state, {:continue, :refresh}}
    else
      _invalid -> {:stop, :invalid_catalog_refresher_configuration}
    end
  end

  @impl true
  def handle_continue(:refresh, state) do
    {:noreply, start_refresh(state)}
  end

  @impl true
  def handle_call(:refresh, from, state) do
    state = %{state | waiters: [from | state.waiters]}
    {:noreply, start_refresh(state)}
  end

  def handle_call(:status, _from, state) do
    {:reply, public_status(state), state}
  end

  def handle_call(:check_staleness, _from, state) do
    state = expire_if_stale(state)
    result = if state.expired?, do: :expired, else: :fresh
    {:reply, result, state}
  end

  @impl true
  def handle_info({reference, outcome}, %{task: %{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    cancel_timer(state.task_timeout_timer)

    state = %{state | task: nil, task_timeout_timer: nil}
    {:noreply, finish_refresh(outcome, state)}
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %{task: %{ref: reference}} = state
      ) do
    cancel_timer(state.task_timeout_timer)
    state = %{state | task: nil, task_timeout_timer: nil}
    {:noreply, finish_refresh({:error, :catalog_refresh_failed}, state)}
  end

  def handle_info(
        {:vxpipe_remote_mcp_refresh_timeout, reference},
        %{task: %{ref: reference}} = state
      ) do
    _ = Task.shutdown(state.task, :brutal_kill)
    state = %{state | task: nil, task_timeout_timer: nil}
    {:noreply, finish_refresh({:error, :refresh_timeout}, state)}
  end

  def handle_info(
        {:vxpipe_remote_mcp_refresh_due, generation},
        %{refresh_timer: {_timer, generation}} = state
      ) do
    {:noreply, start_refresh(%{state | refresh_timer: nil})}
  end

  def handle_info(
        {:vxpipe_remote_mcp_catalog_expiry, generation},
        %{expiry_generation: generation} = state
      ) do
    state = %{state | expiry_generation: nil, expiry_timer: nil}
    {:noreply, expire_if_stale(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{task: nil}), do: :ok

  def terminate(_reason, state) do
    _ = Task.shutdown(state.task, :brutal_kill)
    :ok
  end

  defp start_refresh(%{task: task} = state) when task != nil, do: state

  defp start_refresh(state) do
    cancel_refresh_timer(state.refresh_timer)
    {source_module, source_options} = state.source
    refresh_options = state.refresh_options

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        CatalogRefreshCycle.run({source_module, source_options}, refresh_options)
      end)

    timeout_timer =
      Process.send_after(
        self(),
        {:vxpipe_remote_mcp_refresh_timeout, task.ref},
        state.refresh_timeout_ms
      )

    %{state | refresh_timer: nil, task: task, task_timeout_timer: timeout_timer}
  rescue
    _exception -> finish_refresh({:error, :catalog_refresh_failed}, state)
  catch
    :exit, _reason -> finish_refresh({:error, :catalog_refresh_failed}, state)
  end

  defp finish_refresh(:ok, state) do
    state
    |> mark_fresh()
    |> reply_waiters(:ok)
    |> schedule_refresh()
  end

  defp finish_refresh({:error, _reason} = outcome, state) do
    state
    |> Map.put(:last_outcome, outcome)
    |> expire_if_stale()
    |> reply_waiters(outcome)
    |> schedule_refresh()
  end

  defp mark_fresh(state) do
    {:ok, now_ms} = current_time(state.clock)

    %{state | expired?: false, last_outcome: :ok, last_success_at_ms: now_ms}
    |> schedule_expiry(state.stale_after_ms)
  end

  defp expire_if_stale(%{expired?: true} = state), do: state

  defp expire_if_stale(state) do
    case current_time(state.clock) do
      {:ok, now_ms} -> expire_at(now_ms, state)
      {:error, _reason} -> schedule_expiry(state, state.refresh_interval_ms)
    end
  end

  defp expire_at(now_ms, state) do
    elapsed_ms = max(now_ms - state.last_success_at_ms, 0)

    if elapsed_ms >= state.stale_after_ms do
      case publish_empty(state.catalog_store) do
        :ok -> %{state | expired?: true}
        {:error, _reason} -> schedule_expiry(state, state.refresh_interval_ms)
      end
    else
      schedule_expiry(state, state.stale_after_ms - elapsed_ms)
    end
  end

  defp publish_empty(catalog_store) do
    with {:ok, empty} <- IntegrationCatalog.new(application: %{}, tenants: %{}) do
      CatalogStore.publish(catalog_store, empty)
    end
  catch
    :exit, _reason -> {:error, :catalog_store_unavailable}
  end

  defp schedule_refresh(state) do
    cancel_refresh_timer(state.refresh_timer)
    generation = make_ref()

    timer =
      Process.send_after(
        self(),
        {:vxpipe_remote_mcp_refresh_due, generation},
        state.refresh_interval_ms
      )

    %{state | refresh_timer: {timer, generation}}
  end

  defp schedule_expiry(state, delay_ms) do
    cancel_timer(state.expiry_timer)
    generation = make_ref()

    timer =
      Process.send_after(
        self(),
        {:vxpipe_remote_mcp_catalog_expiry, generation},
        delay_ms
      )

    %{state | expiry_generation: generation, expiry_timer: timer}
  end

  defp reply_waiters(state, outcome) do
    Enum.each(state.waiters, &GenServer.reply(&1, outcome))
    %{state | waiters: []}
  end

  defp public_status(state) do
    %{
      expired?: state.expired?,
      last_outcome: state.last_outcome,
      refreshing?: state.task != nil
    }
  end

  defp current_time(clock) do
    case clock.() do
      milliseconds when is_integer(milliseconds) -> {:ok, milliseconds}
      _invalid -> {:error, :invalid_clock}
    end
  rescue
    _exception -> {:error, :invalid_clock}
  catch
    :exit, _reason -> {:error, :invalid_clock}
  end

  defp cancel_refresh_timer(nil), do: :ok
  defp cancel_refresh_timer({timer, _generation}), do: cancel_timer(timer)

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: true, info: false)
end
