defmodule Vxpipe.CallEngine.Diagnostics.SourceCoordinator do
  @moduledoc "One prospective discovery at a time, with separately bounded source workers."
  use GenServer
  alias Vxpipe.CallEngine.Capability.SpeechToText

  alias Vxpipe.CallEngine.Diagnostics.{
    AttachmentLease,
    CaptureHandoff,
    SettingsProjection,
    SourceAttachment
  }

  alias Vxpipe.CallEngine.RoomAuthority.DiagnosticSources

  def start_link(options),
    do: GenServer.start_link(__MODULE__, options, name: Keyword.fetch!(options, :coordinator))

  def scan(coordinator), do: GenServer.call(coordinator, :scan, 2_000)
  def status(coordinator), do: GenServer.call(coordinator, :status, 250)

  @impl true
  def init(options) do
    state =
      options
      |> Keyword.take([
        :registry,
        :projection,
        :workers,
        :runtime,
        :collector,
        :maximum_sources,
        :attachment_gate,
        :poll_interval_ms
      ])
      |> Map.new()

    state =
      Map.merge(state, %{
        active: %{},
        attaching: nil,
        coordinator: self(),
        pending: nil,
        room: nil,
        cursor: nil,
        audit_cursor: nil,
        timer: nil,
        last_reason: :not_scanned
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

  def handle_info({reference, result}, %{attaching: %{task: %{ref: reference}}} = state) do
    attempt = state.attaching
    Process.cancel_timer(attempt.timer)
    Process.demonitor(reference, [:flush])
    Process.unlink(attempt.task.pid)
    state = %{state | attaching: nil}
    state = accept_attachment(state, attempt.lease, result)
    AttachmentLease.finish(attempt.lease)
    {:noreply, state}
  end

  def handle_info(
        {:attachment_timeout, reference},
        %{attaching: %{task: %{ref: reference}}} = state
      ),
      do: {:noreply, %{cancel_attachment(state) | last_reason: :attachment_timeout}}

  def handle_info(
        {:DOWN, reference, :process, _, _},
        %{attaching: %{task: %{ref: reference}}} = state
      ),
      do: {:noreply, %{cancel_attachment(state) | last_reason: :attachment_unavailable}}

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

    {:noreply, %{state | active: active, room: nil}}
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
    case AttachmentLease.reserve(state.attachment_gate, self()) do
      {:ok, lease} ->
        options = Map.put(state, :attachment_lease, lease)

        task =
          Task.async(fn ->
            AttachmentLease.operation(lease, fn ->
              SourceAttachment.start(candidate, packet, options)
            end)
          end)

        timer =
          Process.send_after(
            self(),
            {:attachment_timeout, task.ref},
            AttachmentLease.remaining(lease)
          )

        {:noreply,
         %{state | attaching: %{task: task, lease: lease, timer: timer}, last_reason: :attaching}}

      _ ->
        {:noreply, %{state | last_reason: :attachment_capacity}}
    end
  end

  defp accept_attachment(state, lease, {:ok, entry}) do
    if SourceAttachment.current?(entry) and CaptureHandoff.current?(entry.input) and
         CaptureHandoff.current?(entry.output) and AttachmentLease.adopt(lease) do
      entry = Map.put(entry, :monitor, Process.monitor(entry.worker))

      %{
        state
        | active: Map.put(state.active, entry.context.capability, entry),
          last_reason: :attached
      }
    else
      AttachmentLease.cancel(lease)
      SourceAttachment.close(entry)
      %{state | last_reason: :stale_source}
    end
  end

  defp accept_attachment(state, lease, {:error, reason}) do
    AttachmentLease.cancel(lease)
    %{state | last_reason: reason}
  end

  defp cancel_attachment(%{attaching: nil} = state), do: state

  defp cancel_attachment(state) do
    attempt = state.attaching
    AttachmentLease.cancel(attempt.lease)
    Process.cancel_timer(attempt.timer)
    Process.unlink(attempt.task.pid)
    Process.exit(attempt.task.pid, :kill)
    Process.demonitor(attempt.task.ref, [:flush])
    AttachmentLease.finish(attempt.lease)
    %{state | attaching: nil}
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
    state = prune(state)

    case SettingsProjection.grant(state.projection) do
      {:ok, grant} ->
        state = audit_active(state)

        cond do
          state.pending != nil or state.attaching != nil ->
            state

          map_size(state.active) >= state.maximum_sources ->
            %{state | last_reason: :source_capacity}

          true ->
            scan_room(state, grant)
        end

      _ ->
        %{revoke(state) | last_reason: :settings_unavailable, room: nil, cursor: nil}
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

    %{
      state
      | active: active,
        room: if(map_size(active) == map_size(state.active), do: state.room)
    }
  end

  defp scan_room(%{room: nil} = state, grant) do
    case next_room(state.registry, state.cursor) do
      nil -> %{state | last_reason: :no_rooms, cursor: nil}
      room -> scan_room(%{state | room: {room, nil}, cursor: room}, grant)
    end
  end

  defp scan_room(%{room: {room, cursor}} = state, grant) do
    case DiagnosticSources.query(room, cursor, 32) do
      {:ok, page} ->
        case Enum.find(page.sources, &(not Map.has_key?(state.active, &1.capability))) do
          nil ->
            %{
              state
              | room: if(page.next_cursor, do: {room, page.next_cursor}),
                last_reason: :no_candidates
            }

          source ->
            candidate = %{
              room: room,
              cursor: cursor,
              identity: page.identity,
              agent: page.agent,
              source: source,
              grant: grant
            }

            state = %{state | room: {room, source.connection_id}}
            discover(state, candidate)
        end

      _ ->
        Enum.each(state.active, fn {_, entry} ->
          if entry.room == room, do: SourceAttachment.close(entry)
        end)

        %{state | room: nil, last_reason: :room_unavailable}
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
           SpeechToText.discover_diagnostics(
             candidate.source.capability,
             candidate.agent,
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

  defp next_room(registry, cursor) do
    rooms =
      Registry.select(registry, [
        {{{:"$1", :"$2"}, :"$3", :_}, [{:is_binary, :"$1"}, {:is_binary, :"$2"}], [:"$3"]}
      ])

    rooms = Enum.sort(rooms)
    Enum.find(rooms, &(cursor == nil or &1 > cursor)) || List.first(rooms)
  rescue
    _ -> nil
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
      pending?: state.pending != nil or state.attaching != nil,
      last_reason: state.last_reason
    }
end
