defmodule Vxpipe.CallEngine.Archive.Subscriber do
  @moduledoc false

  use GenServer

  alias Vxpipe.CallEngine.Archive.{Fact, Handoff, Subscriber.State}
  alias Vxpipe.CallEngine.Id

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
         drain_timer: nil,
         archive_context: nil,
         source_reason: nil,
         completion_enqueued?: false,
         completion_finished?: false
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
      {:ok, {:source_stopped, reason}} -> state |> begin_drain(reason) |> continue()
      :error -> {:noreply, state}
    end
  end

  def handle_info(:write_current, %State{current: nil} = state), do: continue(state)

  def handle_info(:write_current, %State{writer_task: nil} = state) do
    {_origin, value} = state.current

    task =
      Task.Supervisor.async_nolink(
        Vxpipe.CallEngine.ArchiveWriterTaskSupervisor,
        fn -> safe_write(state.writer, value) end
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
        {:DOWN, reference, :process, _pid, reason},
        %State{source_monitor: reference} = state
      ) do
    state |> begin_drain(reason) |> continue()
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
    state = state |> capture_archive_context(fact) |> enqueue_entry({:handoff, fact})
    start_next(state)
  end

  defp enqueue_entry(state, entry) do
    %{state | pending: :queue.in(entry, state.pending)}
  end

  defp enqueue_completion(state, fact) do
    state
    |> Map.put(:completion_enqueued?, true)
    |> enqueue_entry({:completion, fact})
    |> start_next()
  end

  defp capture_archive_context(state, %Fact{} = fact) do
    context = %{
      tenant_id: fact.tenant_id,
      call_id: fact.call_id,
      room_id: fact.room_id,
      incarnation_id: fact.incarnation_id,
      source_policy: fact.source_policy,
      maximum_sequence: fact.sequence
    }

    case state.archive_context do
      nil ->
        %{state | archive_context: context}

      %{tenant_id: tenant_id, call_id: call_id, incarnation_id: incarnation_id} = existing
      when tenant_id == fact.tenant_id and call_id == fact.call_id and
             incarnation_id == fact.incarnation_id ->
        maximum_sequence = max(existing.maximum_sequence, fact.sequence)
        %{state | archive_context: %{existing | maximum_sequence: maximum_sequence}}

      _conflicting_context ->
        state
    end
  end

  defp capture_archive_context(state, _fact), do: state

  defp start_next(%State{current: nil, writer_task: nil} = state) do
    case :queue.out(state.pending) do
      {{:value, entry}, pending} ->
        send(self(), :write_current)
        %{state | current: entry, pending: pending}

      {:empty, _pending} ->
        state
    end
  end

  defp start_next(state), do: state

  defp accepted(%State{current: {:handoff, _fact}} = state) do
    :ok = Handoff.acknowledge(state.handoff)
    state |> Map.put(:current, nil) |> start_next()
  end

  defp accepted(%State{current: {:completion, _fact}} = state) do
    state
    |> Map.put(:current, nil)
    |> Map.put(:completion_finished?, true)
    |> start_next()
  end

  defp discarded(%State{current: {:handoff, _fact}} = state) do
    :ok = Handoff.discard(state.handoff)
    state |> Map.put(:current, nil) |> start_next()
  end

  defp discarded(%State{current: {:completion, _fact}} = state) do
    state
    |> Map.put(:current, nil)
    |> Map.put(:completion_finished?, true)
    |> start_next()
  end

  defp retry(state), do: retry(state, :writer_retry)

  defp retry(state, _reason) do
    :ok = Handoff.retry(state.handoff)
    Process.send_after(self(), :retry_current, state.retry_delay_ms)
    state
  end

  defp begin_drain(%State{closing?: true} = state, _reason), do: state

  defp begin_drain(state, reason) do
    Handoff.close(state.handoff)
    demonitor_source(state.source_monitor)
    timer = Process.send_after(self(), :drain_timeout, state.drain_timeout_ms)

    %{
      state
      | closing?: true,
        source_monitor: nil,
        drain_timer: timer,
        source_reason: reason
    }
  end

  defp monitor_source(%State{source_monitor: nil, closing?: false} = state, source) do
    %{state | source_monitor: Process.monitor(source)}
  end

  defp monitor_source(state, _source), do: state

  defp continue(state) do
    state = maybe_enqueue_completion(state)

    if drained?(state) do
      cancel_timer(state.drain_timer)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp drained?(state) do
    state.closing? and is_nil(state.current) and is_nil(state.writer_task) and
      :queue.is_empty(state.pending) and Handoff.stats(state.handoff).pending == 0 and
      (is_nil(state.archive_context) or state.completion_finished?)
  end

  defp maybe_enqueue_completion(%State{archive_context: nil} = state), do: state
  defp maybe_enqueue_completion(%State{closing?: false} = state), do: state
  defp maybe_enqueue_completion(%State{completion_enqueued?: true} = state), do: state

  defp maybe_enqueue_completion(state) do
    if is_nil(state.current) and is_nil(state.writer_task) and :queue.is_empty(state.pending) and
         Handoff.stats(state.handoff).pending == 0 do
      enqueue_completion(state, completion_fact(state))
    else
      state
    end
  end

  defp completion_fact(state) do
    context = state.archive_context
    stats = Handoff.stats(state.handoff)

    Fact.new!(
      id: Id.generate(:event),
      kind: :archive_stream_closed,
      sequence: context.maximum_sequence + 1,
      tenant_id: context.tenant_id,
      call_id: context.call_id,
      room_id: context.room_id,
      incarnation_id: context.incarnation_id,
      occurred_at: DateTime.utc_now(:millisecond),
      source_policy: context.source_policy,
      payload: %{
        "accepted" => stats.accepted,
        "discarded" => stats.discarded,
        "incomplete" => stats.incomplete?,
        "overflow" => stats.overflow,
        "retries" => stats.retries,
        "source_reason" => state.source_reason,
        "unavailable" => stats.unavailable
      }
    )
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
