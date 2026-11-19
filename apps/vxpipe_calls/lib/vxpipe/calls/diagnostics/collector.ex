defmodule Vxpipe.Calls.Diagnostics.Collector do
  @moduledoc "Source-owned live timing collection with bounded capture, reports and persistence drain."
  use GenServer
  alias Vxpipe.CallEngine.Diagnostics.{AttachmentLease, CaptureHandoff, LiveReport}
  alias Vxpipe.Calls.{LatencyRun, TurnDiagnostic}
  alias Vxpipe.Calls.Diagnostics.{Handoff, Supervisor, Writer}

  def start_link(options) do
    case AttachmentLease.remaining(Keyword.get(options, :attachment_lease)) do
      0 -> {:error, :unavailable}
      timeout -> GenServer.start_link(__MODULE__, options, timeout: timeout)
    end
  end

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}

  def handoff(pid), do: GenServer.call(pid, :handoff, 250)
  def close(pid, reason), do: GenServer.call(pid, {:close, reason}, 1_000)

  @impl true
  def init(options) do
    lease = Keyword.get(options, :attachment_lease)

    with true <- AttachmentLease.current?(lease),
         {:ok, run} <- LatencyRun.new(Map.from_struct(Keyword.fetch!(options, :run))),
         run = compact(run),
         {:ok, capture} <-
           CaptureHandoff.new(self(),
             owner: Keyword.fetch!(options, :owner),
             projection: Keyword.fetch!(options, :projection)
           ),
         true <- elem(capture.grant, 0) == run.settings_revision,
         {:ok, writer} <-
           AttachmentLease.operation(lease, fn ->
             Supervisor.start_writer(
               Keyword.merge(Keyword.fetch!(options, :writer_options),
                 owner: self(),
                 observer: self()
               ),
               Keyword.fetch!(options, :writer_supervisor)
             )
           end),
         true <- AttachmentLease.current?(lease) do
      Process.monitor(writer)

      Enum.each(
        [Keyword.fetch!(options, :owner), Keyword.fetch!(options, :coordinator)],
        &Process.monitor/1
      )

      writes = Writer.handoff(writer)

      state = %{
        run: run,
        attachment_lease: lease,
        capture: capture,
        writer: writer,
        writes: writes,
        reports:
          LiveReport.new(
            %{
              generation: Keyword.fetch!(options, :generation),
              clock_id: run.clock_id,
              origin_us: Keyword.fetch!(options, :origin_us)
            },
            Keyword.get(options, :report_options, [])
          ),
        sent: %{},
        unsettled: 1,
        finishing: nil,
        deadline_timer: nil,
        observer: Keyword.get(Keyword.fetch!(options, :writer_options), :observer),
        timer: nil,
        heartbeat_at: System.monotonic_time(:millisecond),
        utc_now: Keyword.get(options, :utc_now, &DateTime.utc_now/0)
      }

      with true <- AttachmentLease.current?(lease) and CaptureHandoff.current?(capture),
           :ok <- Handoff.offer(writes, {:run, run}) do
        {:ok, schedule(state)}
      else
        _ ->
          CaptureHandoff.close(capture)
          {:stop, :storage_unavailable}
      end
    else
      _ -> {:stop, :unavailable}
    end
  end

  @impl true
  def handle_call(:handoff, _from, state) do
    if AttachmentLease.current?(state.attachment_lease) and CaptureHandoff.current?(state.capture),
      do: {:reply, state.capture, state},
      else: {:reply, {:error, :unavailable}, begin_finish(state, closure_reason(state))}
  end

  def handle_call({:close, reason}, _from, state)
      when reason in [:disabled, :call_ended, :source_changed] do
    {:reply, :ok, begin_finish(state, reason)}
  end

  def handle_call(_request, _from, state), do: {:reply, {:error, :invalid_request}, state}

  @impl true
  def handle_info({:vxpipe_diagnostic_capture, _, _, _, _} = message, state) do
    if AttachmentLease.current?(state.attachment_lease) do
      observe(message, state)
    else
      reason = closure_reason(state)
      CaptureHandoff.close(state.capture)
      observe(message, begin_finish(state, reason))
    end
  end

  def handle_info(:check, %{finishing: reason} = state) when not is_nil(reason),
    do: {:noreply, state}

  def handle_info(:check, state) do
    cond do
      not AttachmentLease.current?(state.attachment_lease) or
          not CaptureHandoff.current?(state.capture) ->
        {:noreply, begin_finish(state, closure_reason(state))}

      CaptureHandoff.overflowed?(state.capture) ->
        {:noreply, begin_finish(state, :observer_overloaded)}

      Handoff.stats(state.writes).discarded > 0 ->
        {:noreply, begin_finish(state, :storage_loss)}

      System.monotonic_time(:millisecond) - state.heartbeat_at >= 1_000 ->
        heartbeat(state)

      true ->
        {:noreply, schedule(state)}
    end
  end

  def handle_info({:DOWN, _, :process, writer, _}, %{writer: writer} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, _, :process, _, _}, state) do
    CaptureHandoff.close(state.capture)
    {:noreply, begin_finish(state, closure_reason(state))}
  end

  def handle_info({:diagnostic_settled, writer, outcome} = message, %{writer: writer} = state)
      when outcome in [:stored, :discarded] and state.unsettled > 0 do
    state = %{state | unsettled: state.unsettled - 1}
    if state.observer, do: send(state.observer, message)
    if state.finishing, do: send(self(), :finish_check)
    state = if outcome == :discarded, do: add_reason(state, :storage_loss), else: state
    {:noreply, state}
  end

  def handle_info(:finish_check, %{finishing: reason} = state) when not is_nil(reason) do
    if state.unsettled == 0,
      do: {:stop, :normal, finish(state, reason)},
      else: {:noreply, state}
  end

  def handle_info(:collector_deadline, %{finishing: reason} = state) when not is_nil(reason),
    do: {:stop, :normal, finish(add_reason(state, :storage_loss), reason)}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    CaptureHandoff.close(state.capture)
    if state.timer, do: Process.cancel_timer(state.timer)
    if state.deadline_timer, do: Process.cancel_timer(state.deadline_timer)
    :ok
  end

  @impl true
  def format_status(status),
    do:
      status
      |> Map.put(:state, :redacted)
      |> Map.put(:message, :redacted)
      |> Map.put(:reason, :redacted)
      |> Map.put(:log, [])

  defp closure_reason(state),
    do: CaptureHandoff.closed_reason(state.capture) || :lease_expired

  defp observe(message, state) do
    case CaptureHandoff.message(state.capture, message) do
      {:ok, packet, charge} ->
        result = LiveReport.observe(state.reports, packet)
        CaptureHandoff.release(state.capture, charge, :processed)

        case result do
          {:ok, reports} -> persist(record_loss(%{state | reports: reports}, packet))
          {:error, :conflicting_evidence} -> {:noreply, begin_finish(state, :clock_uncertain)}
          _ -> {:noreply, begin_finish(state, :observer_overloaded)}
        end

      {:error, :revoked} ->
        {:noreply, begin_finish(state, closure_reason(state))}

      :error ->
        {:noreply, state}
    end
  end

  defp persist(state) do
    result =
      Enum.reduce_while(LiveReport.reports(state.reports), {:ok, state}, fn report,
                                                                            {:ok, state} ->
        if Map.get(state.sent, report.turn_id) == report.revision do
          {:cont, {:ok, state}}
        else
          attributes =
            report
            |> Map.drop([:durations_us, :metric_reasons, :quality])
            |> Map.merge(%{run_id: state.run.id, source_epoch: state.run.source_epoch})

          with {:ok, turn} <- TurnDiagnostic.new(attributes),
               :ok <-
                 Handoff.offer(
                   state.writes,
                   {:turn, state.run.tenant_key, state.run.call_id, state.run.incarnation_id,
                    turn}
                 ) do
            {:cont,
             {:ok,
              %{
                state
                | sent: Map.put(state.sent, report.turn_id, report.revision),
                  unsettled: state.unsettled + 1
              }}}
          else
            _ -> {:halt, {:error, state}}
          end
        end
      end)

    case result do
      {:ok, state} -> {:noreply, state}
      {:error, state} -> {:noreply, begin_finish(state, :storage_loss)}
    end
  end

  defp heartbeat(state) do
    run = next_run(state)

    case Handoff.offer(state.writes, {:run, run}) do
      :ok ->
        {:noreply,
         schedule(%{
           state
           | run: run,
             heartbeat_at: System.monotonic_time(:millisecond),
             unsettled: state.unsettled + 1
         })}

      _ ->
        {:noreply, begin_finish(state, :storage_loss)}
    end
  end

  defp next_run(state) do
    now = state.utc_now.()

    now =
      if DateTime.compare(now, state.run.heartbeat_at) == :lt,
        do: state.run.heartbeat_at,
        else: now

    %{
      state.run
      | revision: state.run.revision + 1,
        heartbeat_at: now,
        counts: Map.merge(state.run.counts, LiveReport.counts(state.reports)),
        unattached_segments: LiveReport.unattached_segments(state.reports)
    }
  end

  defp begin_finish(%{finishing: reason} = state, _new_reason) when not is_nil(reason), do: state

  defp begin_finish(state, reason) do
    CaptureHandoff.close(state.capture)
    send(self(), :finish_check)

    %{
      state
      | finishing: reason,
        deadline_timer: Process.send_after(self(), :collector_deadline, 2_000)
    }
  end

  defp record_loss(state, {:reset, _, reason, _}) do
    case reason do
      :provider_turn_settled -> state
      :source_replaced -> add_reason(state, :source_changed)
      :inference_failed -> add_reason(state, :observer_unavailable)
      other -> add_reason(state, other)
    end
  end

  defp record_loss(state, _packet), do: state

  defp add_reason(state, reason),
    do: %{state | run: %{state.run | reasons: Enum.uniq([reason | state.run.reasons])}}

  defp compact(value) when is_binary(value), do: :binary.copy(value)
  defp compact(value) when is_list(value), do: Enum.map(value, &compact/1)

  defp compact(value) when is_map(value),
    do: Map.new(Map.to_list(value), fn {key, entry} -> {key, compact(entry)} end)

  defp compact(value), do: value

  defp finish(state, reason) do
    CaptureHandoff.close(state.capture)

    state =
      if Handoff.stats(state.writes).discarded > 0,
        do: add_reason(state, :storage_loss),
        else: state

    state =
      if CaptureHandoff.overflowed?(state.capture),
        do: add_reason(state, :observer_overloaded),
        else: state

    run = next_run(state)

    run = %{
      run
      | state: if(reason == :call_ended and run.reasons == [], do: :closed, else: :incomplete),
        closed_at: run.heartbeat_at,
        reasons: Enum.uniq([reason | run.reasons])
    }

    _ = Handoff.offer(state.writes, {:run, run})

    try do
      Writer.drain(state.writer)
    catch
      :exit, _ -> :ok
    end

    %{state | run: run}
  end

  defp schedule(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :check, 250)}
  end
end
