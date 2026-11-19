defmodule Vxpipe.CallEngine.Diagnostics.RoomService do
  @moduledoc "Reconciles accepted STT inputs for one room; optional work stays outside call callbacks."
  use GenServer
  alias Vxpipe.CallEngine.Capability.SpeechToText

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsProjection,
    SourceAttachment,
    SourceAdmission,
    SourcePort
  }

  alias Vxpipe.CallEngine.RoomAuthority.DiagnosticInputs

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :service))

  def address(identity),
    do: Vxpipe.CallEngine.Diagnostics.RoomSupervisor.address(identity, :service)

  def notify_room(identity) do
    case GenServer.whereis(address(identity)) do
      pid when is_pid(pid) -> notify(pid)
      nil -> :ok
    end
  end

  def notify(service), do: GenServer.cast(service, :reconcile)

  def scan(coordinator), do: GenServer.call(coordinator, :scan, 2_000)
  def status(coordinator), do: GenServer.call(coordinator, :status, 250)

  @impl true
  def init(options) do
    state =
      options
      |> Keyword.validate!([
        :service,
        :room,
        :workers,
        :runner,
        :port,
        :source_admission,
        poll_interval_ms: 250
      ])
      |> Map.new()

    unless state.poll_interval_ms in 10..1_000,
      do: raise(ArgumentError, "invalid room diagnostics interval")

    state = Map.update!(state, :room, &GenServer.whereis/1)

    state =
      Map.merge(state, %{
        active: %{},
        attaching: nil,
        coordinator: self(),
        pending: nil,
        cursor: nil,
        audit_cursor: nil,
        timer: nil,
        last_reason: :not_scanned,
        port_pid: nil,
        port_monitor: nil,
        room_monitor: Process.monitor(state.room),
        projection: nil,
        runtime: nil,
        collector: nil,
        maximum_sources: 32
      })

    {:ok, schedule(state), {:continue, :scan}}
  end

  @impl true
  def handle_continue(:scan, state), do: {:noreply, step(state)}
  @impl true
  def handle_call(:scan, _from, state) do
    state = step(state)
    {:reply, summary(state), state}
  end

  def handle_call(:status, _from, state), do: {:reply, summary(state), state}

  @impl true
  def handle_cast(:reconcile, state), do: {:noreply, step(state)}

  @impl true
  def handle_info(:scan, state), do: {:noreply, state |> step() |> schedule()}

  def handle_info({:vxpipe_diagnostic_capture, _, _, _, _} = message, %{pending: pending} = state)
      when pending != nil do
    case CaptureHandoff.message(pending.handoff, message) do
      {:ok, packet, charge} ->
        CaptureHandoff.release(pending.handoff, charge, :processed)

        if System.monotonic_time(:millisecond) < pending.deadline do
          accept_discovery(state, packet)
        else
          {:noreply, %{clear_pending(state) | last_reason: :source_timeout}}
        end

      {:error, :revoked} ->
        {:noreply, clear_pending(state)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(
        {:attachment_result, reference, result},
        %{attaching: %{reference: reference}} = state
      ) do
    attempt = state.attaching
    Process.cancel_timer(attempt.timer)
    state = %{state | attaching: nil}
    state = accept_attachment(state, attempt.lease, result)
    {:noreply, state}
  end

  def handle_info(
        {:attachment_timeout, reference},
        %{attaching: %{reference: reference, expired?: false}} = state
      ),
      do: {:noreply, %{cancel_attachment(state) | last_reason: :attachment_timeout}}

  def handle_info({:DOWN, ref, :process, _, _}, %{room_monitor: ref} = state),
    do: {:stop, :normal, revoke(state)}

  def handle_info({:DOWN, ref, :process, _, _}, %{port_monitor: ref} = state),
    do: {:noreply, %{revoke(state) | port_pid: nil, port_monitor: nil, last_reason: :unavailable}}

  def handle_info({:DOWN, reference, :process, _worker, _reason}, state) do
    active =
      Enum.reduce(state.active, state.active, fn {capability, entry}, active ->
        if entry.monitor == reference do
          SourceAttachment.close(entry)
          Map.delete(active, capability)
        else
          active
        end
      end)

    {:noreply, %{state | active: active}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = revoke(state)
    Process.cancel_timer(state.timer)
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

  defp accept_discovery(state, {:provider_profile, canonical, provider, profile} = packet) do
    supported? =
      match?(%{acknowledged: %{"model_id" => "scribe_v2_realtime"}, missing: []}, profile) and
        match?(
          {:ok, _},
          Vxpipe.Providers.ElevenLabs.Scribe.validate_acknowledgement(
            profile,
            :vad,
            "scribe_v2_realtime"
          )
        )

    if supported? and state.pending.profile in [nil, packet] do
      pending = %{state.pending | profile: {:provider_profile, canonical, provider, profile}}
      finish_ready(%{state | pending: pending})
    else
      {:noreply, %{clear_pending(state) | last_reason: :profile_unavailable}}
    end
  end

  defp accept_discovery(state, {:source_ready, _, _, _, _, _, _, _, _} = packet) do
    if state.pending.source in [nil, packet],
      do: finish_ready(%{state | pending: %{state.pending | source: packet}}),
      else: {:noreply, %{clear_pending(state) | last_reason: :stale_source}}
  end

  defp accept_discovery(state, _packet),
    do: {:noreply, %{clear_pending(state) | last_reason: :invalid_source}}

  defp finish_ready(%{pending: %{source: nil}} = state), do: {:noreply, state}
  defp finish_ready(%{pending: %{profile: nil}} = state), do: {:noreply, state}

  defp finish_ready(state) do
    pending = state.pending
    {:source_ready, generation, _, _, _, _, _, _, _} = pending.source
    {:provider_profile, canonical, provider, profile} = pending.profile
    state = clear_pending(state)

    if generation == canonical do
      candidate =
        Map.merge(pending.candidate, %{provider_generation: provider, provider_profile: profile})

      finish_discovery(state, candidate, pending.source)
    else
      {:noreply, %{state | last_reason: :stale_source}}
    end
  end

  defp finish_discovery(state, candidate, packet) do
    case SourceAdmission.reserve(state.source_admission, self(), state.maximum_sources) do
      {:ok, lease} ->
        start_attachment(state, candidate, packet, lease)

      {:error, reason} ->
        {:noreply, %{state | last_reason: reason}}
    end
  end

  defp start_attachment(state, candidate, packet, lease) do
    case GenServer.whereis(state.runner) do
      runner when is_pid(runner) ->
        reference = make_ref()
        options = Map.put(state, :attachment_lease, lease)

        timer =
          Process.send_after(
            self(),
            {:attachment_timeout, reference},
            AttachmentLease.remaining(lease)
          )

        send(runner, {:attach, self(), reference, candidate, packet, options})

        {:noreply,
         %{
           state
           | attaching: %{reference: reference, lease: lease, timer: timer, expired?: false},
             last_reason: :attaching
         }}

      _ ->
        SourceAdmission.cancel(state.source_admission, lease)
        {:noreply, %{state | last_reason: :attachment_unavailable}}
    end
  end

  defp accept_attachment(state, lease, {:ok, entry}) do
    if SourceAttachment.current?(entry) and CaptureHandoff.current?(entry.input) and
         CaptureHandoff.current?(entry.output) and
         SourceAdmission.adopt(state.source_admission, lease) == :ok do
      entry = Map.put(entry, :monitor, Process.monitor(entry.worker))

      %{
        state
        | active: Map.put(state.active, entry.context.capability, entry),
          last_reason: :attached
      }
    else
      SourceAdmission.cancel(state.source_admission, lease)
      SourceAttachment.close(entry)
      %{state | last_reason: :stale_source}
    end
  end

  defp accept_attachment(state, lease, {:error, reason}) do
    SourceAdmission.cancel(state.source_admission, lease)
    %{state | last_reason: reason}
  end

  defp cancel_attachment(%{attaching: nil} = state), do: state

  defp cancel_attachment(%{attaching: %{expired?: true}} = state), do: state

  defp cancel_attachment(state) do
    attempt = state.attaching
    SourceAdmission.cancel(state.source_admission, attempt.lease)
    Process.cancel_timer(attempt.timer)
    # Keep the slot until the runner replies. A blocked callback or queued request
    # cannot accumulate replacement work after expiry, disable or port loss.
    %{state | attaching: %{attempt | expired?: true}}
  end

  defp audit_active(%{active: active} = state) when map_size(active) == 0, do: state

  defp audit_active(state) do
    keys = state.active |> Map.keys() |> Enum.sort()

    key =
      Enum.find(keys, &(state.audit_cursor == nil or &1 > state.audit_cursor)) || List.first(keys)

    entry = Map.fetch!(state.active, key)
    unless SourceAttachment.current?(entry), do: SourceAttachment.close(entry)
    %{state | audit_cursor: key}
  end

  defp step(state) do
    state = state |> refresh_port() |> prune()

    case SettingsProjection.grant(state.projection) do
      {:ok, grant} ->
        state = audit_active(state)

        cond do
          state.pending != nil or state.attaching != nil ->
            state

          state.port_pid == nil ->
            %{state | last_reason: :unavailable}

          map_size(state.active) >= state.maximum_sources ->
            %{state | last_reason: :capacity_unavailable}

          true ->
            scan_room(state, grant)
        end

      _ ->
        reason = if state.port_pid == nil, do: :unavailable, else: :settings_unavailable
        %{revoke(state) | last_reason: reason, cursor: nil}
    end
  end

  defp prune(state) do
    state =
      if state.pending != nil and
           (System.monotonic_time(:millisecond) >= state.pending.deadline or
              not CaptureHandoff.current?(state.pending.handoff)),
         do: clear_pending(state),
         else: state

    active =
      Enum.reduce(state.active, state.active, fn {capability, entry}, active ->
        cond do
          not Process.alive?(entry.worker) ->
            SourceAttachment.close(entry)
            Process.demonitor(entry.monitor, [:flush])
            Map.delete(active, capability)

          not CaptureHandoff.current?(entry.input) ->
            SourceAttachment.close(entry)
            active

          true ->
            active
        end
      end)

    %{state | active: active}
  end

  defp scan_room(state, grant) do
    case DiagnosticInputs.query(state.room, state.cursor, 32) do
      {:ok, page} ->
        case Enum.find(page.sources, &(not Map.has_key?(state.active, &1.capability))) do
          nil ->
            %{state | cursor: page.next_cursor, last_reason: :no_candidates}

          source ->
            candidate = %{
              room: state.room,
              identity: page.identity,
              source: source,
              grant: grant,
              source_port: state.port_pid
            }

            discover(%{state | cursor: source.connection_id}, candidate)
        end

      _ ->
        %{revoke(state) | cursor: nil, last_reason: :room_unavailable}
    end
  end

  defp refresh_port(state) do
    case SourcePort.read(state.port) do
      {:ok, %{pid: pid}} when pid == state.port_pid ->
        state

      {:ok, port} ->
        state = revoke(state)
        if state.port_monitor, do: Process.demonitor(state.port_monitor, [:flush])

        Map.merge(state, %{
          port_pid: port.pid,
          port_monitor: Process.monitor(port.pid),
          projection: port.projection,
          runtime: port.runtime,
          collector: port.collector,
          maximum_sources: port.maximum_sources,
          cursor: nil
        })

      _ ->
        if state.port_monitor, do: Process.demonitor(state.port_monitor, [:flush])
        %{revoke(state) | port_pid: nil, port_monitor: nil, projection: nil}
    end
  end

  defp discover(state, candidate) do
    deadline = System.monotonic_time(:millisecond) + 500

    with {:ok, handoff} <-
           CaptureHandoff.new(self(),
             owner: candidate.source.capability,
             projection: state.projection,
             maximum_count: 2,
             maximum_bytes: 4_096
           ) do
      if handoff.grant == candidate.grant and
           SpeechToText.discover_input_diagnostics(
             candidate.source.capability,
             handoff,
             250
           ) == :ok and
           SpeechToText.request_diagnostic_profile(candidate.source.capability, handoff, 250) ==
             :ok do
        %{
          state
          | pending: %{
              handoff: handoff,
              candidate: Map.put(candidate, :discovery_token, handoff.token),
              deadline: deadline,
              source: nil,
              profile: nil
            },
            last_reason: :discovering
        }
      else
        CaptureHandoff.close(handoff)
        %{state | last_reason: :source_unavailable}
      end
    else
      _ -> %{state | last_reason: :source_unavailable}
    end
  end

  defp clear_pending(%{pending: nil} = state), do: state

  defp clear_pending(state) do
    CaptureHandoff.close(state.pending.handoff)
    %{state | pending: nil}
  end

  defp revoke(state) do
    Enum.each(state.active, fn {_, entry} -> SourceAttachment.close(entry) end)
    state |> clear_pending() |> cancel_attachment()
  end

  defp schedule(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :scan, state.poll_interval_ms)}
  end

  defp summary(state),
    do: %{
      active_sources: map_size(state.active),
      pending?: state.pending != nil or (state.attaching != nil and not state.attaching.expired?),
      last_reason: state.last_reason
    }
end
