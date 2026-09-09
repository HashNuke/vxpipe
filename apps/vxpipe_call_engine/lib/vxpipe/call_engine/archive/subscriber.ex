defmodule Vxpipe.CallEngine.Archive.Subscriber do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Archive.{Handoff, Subscriber.State}

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{
      id: {__MODULE__, make_ref()},
      start: {__MODULE__, :start_link, [options]},
      restart: :temporary,
      shutdown: 5_000
    }
  end

  @spec handoff(pid()) :: Handoff.t()
  def handoff(subscriber), do: GenServer.call(subscriber, :handoff)

  @impl true
  def init(options) do
    with {:ok, writer} <- writer(options),
         {:ok, capacity} <- positive_integer(options, :maximum_pending_facts),
         {:ok, retry_delay_ms} <- non_negative_integer(options, :retry_delay_ms),
         {:ok, drain_timeout_ms} <- positive_integer(options, :drain_timeout_ms) do
      handoff = Handoff.new(self(), capacity)

      {:ok,
       %State{
         handoff: handoff,
         writer: writer,
         retry_delay_ms: retry_delay_ms,
         drain_timeout_ms: drain_timeout_ms,
         pending: :queue.new(),
         current: nil,
         writer_task: nil,
         source_monitor: nil,
         closing?: false,
         drain_timer: nil
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:handoff, _from, state), do: {:reply, state.handoff, state}

  @impl true
  def handle_info({:vxpipe_archive, kind, token, value}, state) do
    case Handoff.message(state.handoff, {kind, token, value}) do
      {:ok, {:fact, fact}} -> state |> enqueue(fact) |> continue()
      {:ok, {:source_started, source}} -> {:noreply, monitor_source(state, source)}
      {:ok, {:source_stopped, _reason}} -> state |> begin_drain() |> continue()
      :error -> {:noreply, state}
    end
  end

  def handle_info(:write_current, %State{current: nil} = state), do: continue(state)

  def handle_info(:write_current, %State{writer_task: nil} = state) do
    task =
      Task.Supervisor.async_nolink(
        Vxpipe.CallEngine.ArchiveWriterTaskSupervisor,
        fn -> safe_write(state.writer, state.current) end
      )

    {:noreply, %{state | writer_task: task}}
  end

  def handle_info(:retry_current, %State{current: nil} = state), do: continue(state)

  def handle_info(:retry_current, %State{writer_task: nil} = state) do
    send(self(), :write_current)
    {:noreply, state}
  end

  def handle_info({reference, outcome}, %State{writer_task: %Task{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    state = %{state | writer_task: nil}

    case outcome do
      :ok -> state |> accepted() |> continue()
      {:discard, _reason} -> state |> discarded() |> continue()
      {:retry, _reason} -> state |> retry() |> continue()
    end
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, _reason},
        %State{source_monitor: reference} = state
      ) do
    state |> begin_drain() |> continue()
  end

  def handle_info(
        {:DOWN, reference, :process, _pid, reason},
        %State{writer_task: %Task{ref: reference}} = state
      ) do
    state
    |> Map.put(:writer_task, nil)
    |> retry({:writer_exit, reason})
    |> continue()
  end

  def handle_info(:drain_timeout, state) do
    terminate_writer(state.writer_task)
    _abandoned = Handoff.abandon_pending(state.handoff)
    {:stop, :normal, %{state | writer_task: nil, current: nil, pending: :queue.new()}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp enqueue(state, fact) do
    state = %{state | pending: :queue.in(fact, state.pending)}
    start_next(state)
  end

  defp start_next(%State{current: nil, writer_task: nil} = state) do
    case :queue.out(state.pending) do
      {{:value, fact}, pending} ->
        send(self(), :write_current)
        %{state | current: fact, pending: pending}

      {:empty, _pending} ->
        state
    end
  end

  defp start_next(state), do: state

  defp accepted(state) do
    :ok = Handoff.acknowledge(state.handoff)
    state |> Map.put(:current, nil) |> start_next()
  end

  defp discarded(state) do
    :ok = Handoff.discard(state.handoff)
    state |> Map.put(:current, nil) |> start_next()
  end

  defp retry(state), do: retry(state, :writer_retry)

  defp retry(state, _reason) do
    :ok = Handoff.retry(state.handoff)
    Process.send_after(self(), :retry_current, state.retry_delay_ms)
    state
  end

  defp begin_drain(%State{closing?: true} = state), do: state

  defp begin_drain(state) do
    Handoff.close(state.handoff)
    demonitor_source(state.source_monitor)
    timer = Process.send_after(self(), :drain_timeout, state.drain_timeout_ms)
    %{state | closing?: true, source_monitor: nil, drain_timer: timer}
  end

  defp monitor_source(%State{source_monitor: nil, closing?: false} = state, source) do
    %{state | source_monitor: Process.monitor(source)}
  end

  defp monitor_source(state, _source), do: state

  defp continue(state) do
    if drained?(state) do
      cancel_timer(state.drain_timer)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp drained?(state) do
    state.closing? and is_nil(state.current) and is_nil(state.writer_task) and
      :queue.is_empty(state.pending) and Handoff.stats(state.handoff).pending == 0
  end

  defp safe_write({module, context}, fact) do
    case apply(module, :write, [context, fact]) do
      :ok -> :ok
      {:retry, _reason} = retry -> retry
      {:discard, _reason} = discard -> discard
      _invalid -> {:discard, :invalid_writer_outcome}
    end
  rescue
    _error -> {:retry, :writer_exception}
  catch
    :exit, _reason -> {:retry, :writer_exit}
    _kind, _reason -> {:retry, :writer_failure}
  end

  defp writer(options) do
    case Keyword.get(options, :writer) do
      {module, context} when is_atom(module) -> {:ok, {module, context}}
      _invalid -> {:error, :invalid_archive_writer}
    end
  end

  defp positive_integer(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value > 0 -> {:ok, value}
      _invalid -> {:error, {:invalid_archive_option, key}}
    end
  end

  defp non_negative_integer(options, key) do
    case Keyword.get(options, key) do
      value when is_integer(value) and value >= 0 -> {:ok, value}
      _invalid -> {:error, {:invalid_archive_option, key}}
    end
  end

  defp terminate_writer(nil), do: :ok

  defp terminate_writer(%Task{pid: pid}) do
    _result =
      Task.Supervisor.terminate_child(Vxpipe.CallEngine.ArchiveWriterTaskSupervisor, pid)

    :ok
  end

  defp demonitor_source(nil), do: :ok
  defp demonitor_source(reference), do: Process.demonitor(reference, [:flush])

  defp cancel_timer(nil), do: :ok

  defp cancel_timer(reference) do
    _result = Process.cancel_timer(reference)
    :ok
  end
end
