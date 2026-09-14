defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanMediaHandoff do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.Readiness.{Collector, Inventory, Preparation, RoomInventory}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantLifecycle
  alias Vxpipe.CallEngine.{RoomAuthority, RoomCapabilitySupervisor, Telemetry}
  alias Vxpipe.CallEngine.WaitSounds.Player

  @readiness_check_interval_ms 100

  def run(stage, scope, payload) do
    started_at = Telemetry.started_at()

    result =
      try do
        execute(stage, scope, payload)
      rescue
        _exception -> {:error, :handoff_unavailable}
      catch
        :exit, _reason -> {:error, :handoff_unavailable}
      end

    outcome =
      case result do
        {:ok, _value} -> :ok
        {:error, :deadline_elapsed} -> :timeout
        _failure -> :failed
      end

    Telemetry.transfer_phase_stop(started_at, stage, outcome)
    result
  end

  defp execute(:audience, phase, request) do
    scope =
      Map.merge(
        Map.take(phase, [:owner, :attempt_id, :deadline_ms]),
        %{generation: System.unique_integer([:positive, :monotonic])}
      )

    with {:ok, binding} <- RoomAuthority.readiness_binding(phase.authority),
         policy = Authority.snapshot(binding.policy_authority),
         {:ok, connections} <- capture_connections(binding, policy.present_participant_ids),
         :ok <-
           each(connections, fn {_id, connection} ->
             connection.adapter.hold(connection, scope)
           end),
         {:ok, waits} <- play(connections, binding, scope, request, :wait, phase.owner) do
      {:ok, %{scope: scope, connections: connections, waits: waits}}
    end
  end

  defp execute(:recover, phase, %{request: request, text_to_speech: text_to_speech}) do
    scope =
      Map.merge(
        Map.take(phase, [:owner, :attempt_id, :deadline_ms]),
        %{generation: System.unique_integer([:positive, :monotonic])}
      )

    with {:ok, binding} <- RoomAuthority.readiness_binding(phase.authority),
         policy = Authority.snapshot(binding.policy_authority),
         true <- MapSet.member?(policy.present_participant_ids, request.source_participant_id),
         {:ok, candidate} <-
           Authority.preview_presence(binding.policy_authority, policy.present_participant_ids),
         {:ok, connections} <- capture_connections(binding, policy.present_participant_ids),
         :ok <-
           each(connections, fn {_id, connection} ->
             connection.adapter.recover(connection, scope)
           end),
         {:ok, graph} <- Preparation.run(phase.authority, candidate, remaining(scope)),
         {:ok, collector} <- collect(graph.resources, binding, scope),
         :ok <- await_ready(collector, scope, [], {phase, :recovering, nil}),
         :ok <- clear(connections),
         {:ok, cues} <- play(connections, binding, scope, request, :cue),
         :ok <- await_players(cues, :completed, scope, collector),
         :ok <- Collector.refresh(collector),
         :ok <- await_ready(collector, scope),
         :ok <- RoomInventory.validate(phase.authority, graph.inventory, remaining(scope)),
         :ok <-
           each(connections, fn {id, connection} ->
             demand = Map.fetch!(graph.inventory.inventory.connections, id).demand
             connection.adapter.release(connection, scope, demand)
           end) do
      {:ok, %{connections: connections, scope: scope, text_to_speech: text_to_speech}}
    else
      false -> {:error, :source_unavailable}
      error -> error
    end
  end

  defp execute(:prepare, phase, %{request: request, ready: ready}) do
    with {:ok, waits} <- play(ready.connections, ready.binding, ready.scope, request, :wait),
         {:ok, collector} <- collect(ready.graph.resources, ready.binding, ready.scope),
         {:ok, ready} <- prepare_release(Map.put(ready, :waits, waits), collector, phase, request) do
      report_progress(phase, :releasing, [])
      {:ok, Map.delete(ready, :waits)}
    end
  end

  defp execute(:prepare, phase, %{request: request, preparation: preparation}) do
    audience = phase.audience
    scope = audience.scope

    with {:ok, participant} <- prepare_participant(preparation, phase.incarnation_id),
         {:ok, media} <- prepare_media(phase, request, scope),
         joining = Map.drop(media.connections, Map.keys(audience.connections)),
         :ok <- hold(joining, scope),
         {:ok, joining_waits} <- play(joining, media.binding, scope, request, :wait),
         {:ok, graph} <-
           Preparation.run_candidate(phase.authority, media.candidate, Map.to_list(scope)),
         {:ok, collector} <- collect(graph.resources, media.binding, scope),
         prepared =
           Map.merge(media, %{
             scope: scope,
             graph: graph,
             participant: participant,
             waits: audience.waits ++ joining_waits
           }),
         {:ok, ready} <- prepare_release(prepared, collector, phase, request) do
      report_progress(phase, :releasing, [])
      {:ok, Map.delete(ready, :waits)}
    end
  end

  defp execute(:release, phase, ready) do
    with :ok <-
           each(ready.connections, fn {_id, binding} ->
             if binding.attachment.admission == :transfer_preparation,
               do: binding.adapter.adopt(binding, ready.scope),
               else: :ok
           end),
         {:ok, collector} <- collect(ready.graph.resources, ready.binding, ready.scope),
         :ok <- await_ready(collector, ready.scope),
         true <- Authority.snapshot(ready.binding.policy_authority) == ready.candidate.snapshot,
         :ok <-
           each(ready.connections, fn {id, binding} ->
             demand = Map.fetch!(ready.graph.inventory.inventory.connections, id).demand
             binding.adapter.release(binding, ready.scope, demand)
           end),
         {:ok, current} <- RoomAuthority.readiness_binding(phase.authority),
         true <- current.attempt.id == ready.scope.attempt_id do
      {:ok, ready}
    else
      false -> {:error, :handoff_changed}
      error -> error
    end
  end

  defp prepare_participant(%{participant: participant}, _incarnation), do: {:ok, participant}

  defp prepare_participant(preparation, incarnation),
    do: ParticipantLifecycle.prepare(preparation.destination.command, incarnation)

  defp prepare_release(prepared, collector, phase, request) do
    with {:ok, ready} <-
           await_preparation(prepared, collector, phase, request, {phase, :preparing, nil}),
         :ok <- stop_waits(ready.waits, ready.scope),
         :ok <- clear(ready.connections) do
      cue_release(%{ready | waits: []}, collector, phase, request)
    end
  end

  defp cue_release(ready, collector, phase, request) do
    scope = ready.scope
    inventory = {phase.authority, ready.graph.inventory}

    with :ok <- report_progress(phase, :cue, []),
         {:ok, cues} <- play(ready.connections, ready.binding, scope, request, :cue),
         :ok <- await_players(cues, :completed, scope, collector, inventory),
         :ok <- validate_inventory(inventory, scope),
         :ok <- Collector.refresh(collector),
         :ok <- await_ready(collector, scope, [], nil, inventory),
         :ok <- validate_inventory(inventory, scope) do
      {:ok, ready}
    else
      {:error, :stale_candidate} ->
        with :ok <- clear(ready.connections),
             {:ok, waits} <- play(ready.connections, ready.binding, scope, request, :wait),
             do: prepare_release(%{ready | waits: waits}, collector, phase, request)

      error ->
        error
    end
  end

  defp prepare_media(phase, request, scope) do
    with {:ok, initial} <- RoomAuthority.readiness_binding(phase.authority, remaining(scope)),
         {:ok, receipts} <- prepare_private(initial, scope),
         {:ok, binding} <- RoomAuthority.readiness_binding(phase.authority, remaining(scope)),
         base = Authority.snapshot(binding.policy_authority, remaining(scope)),
         present =
           base.present_participant_ids
           |> MapSet.delete(request.source_participant_id)
           |> MapSet.put(request.destination_participant_id),
         {:ok, candidate} <-
           Authority.preview_presence(binding.policy_authority, present, remaining(scope)),
         {:ok, connections} <- capture_connections(binding, present) do
      {:ok,
       %{candidate: candidate, connections: connections, receipts: receipts, binding: binding}}
    end
  end

  defp await_preparation(prepared, collector, phase, request, progress) do
    with {:ok, prepared} <- reconcile_preparation(prepared, collector, phase, request) do
      # Notifications may describe resources removed by reconciliation. Read the
      # collector's current set before deciding whether the handoff can proceed.
      report = Collector.snapshot(collector)
      progress = report_readiness(progress, report.blockers)

      case report.status do
        :ready -> {:ok, prepared}
        :failed -> {:error, report.failure || :readiness_failed}
        :preparing -> await_preparation_change(prepared, collector, phase, request, progress)
      end
    end
  end

  defp await_preparation_change(prepared, collector, phase, request, progress) do
    receive do
      {:vxpipe_readiness_changed, ^collector, _report} ->
        await_preparation(prepared, collector, phase, request, progress)

      {:vxpipe_wait_playback, _player, _episode, {:failed, reason}} ->
        {:error, reason}

      {:DOWN, _monitor, :process, player, _reason} ->
        if player in prepared.waits,
          do: {:error, :playback_unavailable},
          else: await_preparation(prepared, collector, phase, request, progress)
    after
      min(remaining(prepared.scope), @readiness_check_interval_ms) ->
        await_preparation(prepared, collector, phase, request, progress)
    end
  end

  defp reconcile_preparation(prepared, collector, phase, request) do
    if remaining(prepared.scope) == 0 do
      {:error, :deadline_elapsed}
    else
      case RoomInventory.validate(
             phase.authority,
             prepared.graph.inventory,
             remaining(prepared.scope)
           ) do
        :ok ->
          {:ok, prepared}

        {:error, reason} when reason in [:stale_candidate, :room_changed] ->
          refresh_preparation(prepared, collector, phase, request)

        error ->
          error
      end
    end
  end

  defp refresh_preparation(prepared, collector, phase, request) do
    scope = prepared.scope

    with {:ok, media} <- prepare_media(phase, request, scope),
         added = Map.drop(media.connections, Map.keys(prepared.connections)),
         :ok <- hold(added, scope),
         {:ok, waits} <- play(added, media.binding, scope, request, :wait),
         {:ok, graph} <-
           Preparation.run_candidate(phase.authority, media.candidate, Map.to_list(scope)),
         {:ok, _diff} <- Collector.reconcile(collector, scope.attempt_id, graph.resources) do
      {:ok,
       prepared |> Map.merge(media) |> Map.merge(%{graph: graph, waits: prepared.waits ++ waits})}
    end
  end

  defp hold(connections, scope),
    do: each(connections, fn {_id, connection} -> connection.adapter.hold(connection, scope) end)

  defp prepare_private(binding, scope) do
    binding.connections
    |> Enum.filter(fn {_id, connection} -> connection.transfer_attempt_id == scope.attempt_id end)
    |> Enum.reduce_while({:ok, %{}}, fn {id, connection}, {:ok, receipts} ->
      case GenServer.call(
             connection.pid,
             {:vxpipe_prepare_transfer_media, scope.attempt_id},
             remaining(scope)
           ) do
        {:ok, receipt} -> {:cont, {:ok, Map.put(receipts, id, receipt)}}
        error -> {:halt, error}
      end
    end)
  end

  defp capture_connections(binding, present) do
    binding.connections
    |> Enum.filter(fn {_id, connection} ->
      MapSet.member?(present, connection.participant_id) and
        Inventory.media_connection?(connection)
    end)
    |> Enum.reduce_while({:ok, %{}}, fn {id, connection}, {:ok, captured} ->
      case GenServer.call(connection.pid, :vxpipe_connection_readiness, 1_000) do
        {:ok, media} -> {:cont, {:ok, Map.put(captured, id, media)}}
        error -> {:halt, error}
      end
    end)
  end

  defp collect(resources, binding, scope) do
    RoomCapabilitySupervisor.start_readiness(binding.identity.incarnation_id,
      owner: self(),
      attempt_id: scope.attempt_id,
      deadline_ms: scope.deadline_ms,
      resources: resources
    )
  end

  defp await_ready(collector, scope, players \\ [], progress \\ nil, inventory \\ nil) do
    with :ok <- validate_inventory(inventory, scope) do
      receive do
        {:vxpipe_readiness_changed, ^collector, _notification} ->
          case Collector.snapshot(collector) do
            %{status: :ready} ->
              :ok

            %{status: :failed, failure: failure} ->
              {:error, failure || :readiness_failed}

            %{blockers: blockers} ->
              progress = report_readiness(progress, blockers)
              await_ready(collector, scope, players, progress, inventory)
          end

        {:vxpipe_wait_playback, player, _episode, {:failed, reason}} ->
          if player in players,
            do: {:error, reason},
            else: await_ready(collector, scope, players, progress, inventory)

        {:DOWN, _monitor, :process, player, _reason} ->
          if player in players and not completed_player?(player),
            do: {:error, :playback_unavailable},
            else: await_ready(collector, scope, List.delete(players, player), progress, inventory)
      after
        cue_check_timeout(inventory, scope) ->
          if inventory && remaining(scope) > 0,
            do: await_ready(collector, scope, players, progress, inventory),
            else: {:error, :deadline_elapsed}
      end
    end
  end

  defp completed_player?(player) do
    # The player sends completion before exiting. A readiness recheck can selectively
    # receive its DOWN first; leave the drain acknowledgement for await_players.
    receive do
      {:vxpipe_wait_playback, ^player, _episode, :completed} = completion ->
        send(self(), completion)
        true
    after
      0 -> false
    end
  end

  defp report_readiness(nil, _blockers), do: nil

  defp report_readiness({phase, status, previous}, blockers) do
    kinds = blockers |> Enum.map(&blocker_kind(&1.kind)) |> Enum.uniq() |> Enum.sort()
    if kinds != previous, do: report_progress(phase, status, kinds)
    {phase, status, kinds}
  end

  defp report_progress(phase, status, blockers) do
    send(
      phase.owner,
      {:vxpipe_transfer_progress, self(),
       %{
         phase: status,
         blockers: blockers,
         elapsed_ms: max(System.monotonic_time(:millisecond) - phase.started_at_ms, 0)
       }}
    )

    :ok
  end

  defp blocker_kind(kind) when kind in [:speech_to_text, :text_to_speech, :model_inference],
    do: kind

  defp blocker_kind(:speech_to_text_ingress), do: :speech_to_text
  defp blocker_kind(kind) when kind in [:tool_invocations, :remote_tools], do: :tools

  defp blocker_kind(kind)
       when kind in [:recording_writer, :recording_output, :recording, :archive],
       do: :recording

  defp blocker_kind(kind)
       when kind in [:room_mixer, :transcript_router, :call_variables, :live_inspection],
       do: :room_services

  defp blocker_kind(kind)
       when kind in [
              :audio_input,
              :audio_output,
              :audio_subscription,
              :media_connection,
              :media_input,
              :phone_transport,
              :private_output,
              :room_output_binding
            ],
       do: :media

  defp blocker_kind(_kind), do: :other

  defp play(connections, binding, scope, request, mode, owner \\ self()) do
    assets = binding.plan.wait_sound_assets
    episode = System.unique_integer([:positive, :monotonic])

    connections
    |> Enum.group_by(fn {_id, connection} -> connection.identity.participant_id end)
    |> Enum.reduce_while({:ok, []}, fn {participant, outputs}, {:ok, players} ->
      destination = Map.fetch!(binding.plan.participants, request.destination_definition_key)

      slot =
        cond do
          destination.kind == :agent -> :transfer_to_agent
          participant == request.destination_participant_id -> :transfer_joining
          true -> :transfer_to_human
        end

      asset_id = if mode == :cue, do: assets.connection_cue, else: Map.fetch!(assets.slots, slot)

      if asset_id do
        identity =
          binding.identity |> Map.take([:tenant_id, :room_id, :incarnation_id]) |> Map.to_list()

        options =
          identity ++
            [
              owner: owner,
              episode_id: "#{scope.attempt_id}:#{participant}:#{mode}:#{episode}",
              participant_id: participant,
              connection_generation: scope.generation,
              attempt_id: scope.attempt_id,
              phase: mode,
              output_generation: scope.generation,
              sinks: Map.new(outputs, fn {id, connection} -> {id, connection.output} end),
              asset: Map.fetch!(assets.assets, asset_id),
              loop: mode == :wait
            ]

        case RoomCapabilitySupervisor.start_wait_audio(binding.identity.incarnation_id, options) do
          {:ok, player} ->
            if owner == self(), do: Process.monitor(player)
            {:cont, {:ok, [player | players]}}

          error ->
            {:halt, error}
        end
      else
        {:cont, {:ok, players}}
      end
    end)
  end

  defp stop_waits(players, scope) do
    Enum.each(players, &Player.stop/1)
    await_players(players, :stopped, scope)
  end

  defp await_players(players, status, scope, collector \\ nil, inventory \\ nil)

  defp await_players([], _status, _scope, _collector, _inventory), do: :ok

  defp await_players(players, status, scope, collector, inventory) do
    receive do
      {:vxpipe_wait_playback, player, _episode, ^status} ->
        await_players(List.delete(players, player), status, scope, collector, inventory)

      {:vxpipe_wait_playback, _player, _episode, {:failed, reason}} ->
        {:error, reason}

      {:DOWN, _monitor, :process, player, _reason} ->
        if player in players,
          do: {:error, :playback_unavailable},
          else: await_players(players, status, scope, collector, inventory)

      {:vxpipe_readiness_changed, ^collector, _notification} ->
        with :ok <- validate_inventory(inventory, scope) do
          case Collector.snapshot(collector) do
            %{status: :ready} -> await_players(players, status, scope, collector, inventory)
            %{status: :failed, failure: failure} -> {:error, failure || :readiness_failed}
            %{status: :preparing} -> {:error, :readiness_lost}
          end
        else
          {:error, :stale_candidate} -> await_players(players, status, scope)
          error -> error
        end
    after
      cue_check_timeout(collector, scope) ->
        if collector && remaining(scope) > 0 do
          with :ok <- validate_inventory(inventory, scope),
               :ok <- Collector.refresh(collector),
               :ok <- await_ready(collector, scope, players, nil, inventory) do
            await_players(players, status, scope, collector, inventory)
          else
            {:error, :stale_candidate} -> await_players(players, status, scope)
            error -> error
          end
        else
          {:error, :deadline_elapsed}
        end
    end
  end

  defp validate_inventory(nil, _scope), do: :ok

  defp validate_inventory({authority, inventory}, scope) do
    case remaining(scope) do
      0 -> {:error, :deadline_elapsed}
      timeout -> RoomInventory.validate(authority, inventory, timeout)
    end
  end

  defp cue_check_timeout(nil, scope), do: remaining(scope)

  defp cue_check_timeout(_collector, scope),
    do: min(remaining(scope), @readiness_check_interval_ms)

  defp clear(connections) do
    each(connections, fn {_id, binding} ->
      case OutputSink.clear(binding.output) do
        {:ok, _discarded} -> :ok
        error -> error
      end
    end)
  end

  defp each(items, callback) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case callback.(item) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp remaining(scope), do: max(scope.deadline_ms - System.monotonic_time(:millisecond), 0)
end
