defmodule Vxpipe.CallEngine.RoomAuthority.ParticipantTransfer.HumanMediaHandoff do
  @moduledoc false

  alias Vxpipe.CallEngine.Media.OutputSink
  alias Vxpipe.CallEngine.MediaPolicy.Authority
  alias Vxpipe.CallEngine.Readiness.{Collector, Preparation, RoomInventory}
  alias Vxpipe.CallEngine.RoomAuthority.ParticipantLifecycle
  alias Vxpipe.CallEngine.{RoomAuthority, RoomCapabilitySupervisor}
  alias Vxpipe.CallEngine.WaitSounds.Player

  def run(stage, scope, payload) do
    execute(stage, scope, payload)
  rescue
    _exception -> {:error, :handoff_unavailable}
  catch
    :exit, _reason -> {:error, :handoff_unavailable}
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

  defp execute(:recover, phase, request) do
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
         :ok <- await_ready(collector, scope),
         :ok <- clear(connections),
         {:ok, cues} <- play(connections, binding, scope, request, :cue),
         :ok <- await_players(cues, :completed, scope),
         :ok <- Collector.refresh(collector),
         :ok <- await_ready(collector, scope),
         :ok <- RoomInventory.validate(phase.authority, graph.inventory, remaining(scope)),
         :ok <-
           each(connections, fn {id, connection} ->
             demand = Map.fetch!(graph.inventory.inventory.connections, id).demand
             connection.adapter.release(connection, scope, demand)
           end) do
      {:ok, binding}
    else
      false -> {:error, :source_unavailable}
      error -> error
    end
  end

  defp execute(:prepare, phase, %{request: request, preparation: preparation}) do
    audience = phase.audience
    scope = audience.scope

    with {:ok, participant} <-
           ParticipantLifecycle.prepare(
             preparation.destination.command,
             phase.incarnation_id
           ),
         {:ok, initial} <- RoomAuthority.readiness_binding(phase.authority),
         {:ok, receipts} <- prepare_private(initial, scope),
         {:ok, binding} <- RoomAuthority.readiness_binding(phase.authority),
         base = Authority.snapshot(binding.policy_authority),
         present =
           base.present_participant_ids
           |> MapSet.delete(request.source_participant_id)
           |> MapSet.put(request.destination_participant_id),
         {:ok, candidate} <- Authority.preview_presence(binding.policy_authority, present),
         {:ok, connections} <- capture_connections(binding, present),
         joining = Map.drop(connections, Map.keys(audience.connections)),
         :ok <-
           each(joining, fn {_id, connection} ->
             connection.adapter.hold(connection, scope)
           end),
         {:ok, joining_waits} <- play(joining, binding, scope, request, :wait),
         {:ok, graph} <- Preparation.run_candidate(phase.authority, candidate, Map.to_list(scope)),
         {:ok, collector} <- collect(graph.resources, binding, scope),
         :ok <- await_ready(collector, scope),
         :ok <- stop_waits(audience.waits ++ joining_waits, scope),
         :ok <- clear(connections),
         {:ok, cues} <- play(connections, binding, scope, request, :cue),
         :ok <- await_players(cues, :completed, scope),
         :ok <- Collector.refresh(collector),
         :ok <- await_ready(collector, scope),
         :ok <- RoomInventory.validate(phase.authority, graph.inventory, remaining(scope)) do
      {:ok,
       %{
         scope: scope,
         candidate: candidate,
         graph: graph,
         participant: participant,
         connections: connections,
         receipts: receipts,
         binding: binding
       }}
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
    |> Enum.filter(fn {_id, connection} -> MapSet.member?(present, connection.participant_id) end)
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

  defp await_ready(collector, scope) do
    receive do
      {:vxpipe_readiness_changed, ^collector, %{status: :ready}} ->
        :ok

      {:vxpipe_readiness_changed, ^collector, %{status: :failed, failure: failure}} ->
        {:error, failure || :readiness_failed}

      {:vxpipe_readiness_changed, ^collector, _preparing} ->
        await_ready(collector, scope)
    after
      remaining(scope) -> {:error, :deadline_elapsed}
    end
  end

  defp play(connections, binding, scope, request, mode, owner \\ self()) do
    assets = binding.plan.wait_sound_assets

    connections
    |> Enum.group_by(fn {_id, connection} -> connection.identity.participant_id end)
    |> Enum.reduce_while({:ok, []}, fn {participant, outputs}, {:ok, players} ->
      slot =
        if participant == request.destination_participant_id,
          do: :transfer_joining,
          else: :transfer_to_human

      asset_id = if mode == :cue, do: assets.connection_cue, else: Map.fetch!(assets.slots, slot)

      if asset_id do
        identity =
          binding.identity |> Map.take([:tenant_id, :room_id, :incarnation_id]) |> Map.to_list()

        options =
          identity ++
            [
              owner: owner,
              episode_id: "#{scope.attempt_id}:#{participant}:#{mode}",
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
          {:ok, player} -> {:cont, {:ok, [player | players]}}
          error -> {:halt, error}
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

  defp await_players([], _status, _scope), do: :ok

  defp await_players(players, status, scope) do
    receive do
      {:vxpipe_wait_playback, player, _episode, ^status} ->
        await_players(List.delete(players, player), status, scope)

      {:vxpipe_wait_playback, _player, _episode, {:failed, reason}} ->
        {:error, reason}
    after
      remaining(scope) -> {:error, :deadline_elapsed}
    end
  end

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
