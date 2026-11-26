defmodule Vxpipe.CallEngine.Readiness.RecordingOutputs do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Effective
  alias Vxpipe.CallEngine.Readiness.{Inventory, ResourceQuery}
  alias Vxpipe.CallEngine.Recording.EgressReadiness
  alias Vxpipe.CallEngine.RoomMixer.RecordingSelection

  def prepare(captured, connections, mixer_resource \\ nil) do
    required = captured.inventory.recording_participant_ids

    agents =
      for {_key, participant} <- captured.binding.plan.participants,
          participant.kind == :agent,
          MapSet.member?(required, participant.participant_id),
          do: participant.participant_id

    Enum.reduce_while(agents, {:ok, %{}, []}, fn agent, {:ok, tracks, resources} ->
      case prepare_agent(agent, captured, connections, mixer_resource) do
        {:ok, bindings} ->
          # Stable agent artifact: one track per agent using its own source
          # connection identity, independent of which listener(s) carry it.
          # Listener taps are still prepared for readiness; the recorded
          # frames are deduplicated downstream per (source, timestamp).
          modes = [RecordingSelection.stable_agent_mode(agent)]

          dependencies = Enum.flat_map(bindings, &Map.get(&1, :resources, [&1.resource]))
          {:cont, {:ok, Map.put(tracks, agent, modes), resources ++ dependencies}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  # The room track is fed by the egress taps that carry audio to
  # listeners: room-origin frames accepted on any listener connection are
  # deduplicated to one frame per room-clock timestamp downstream. Taps are
  # bound as connections attach, so preparation stays tolerant when no
  # listener currently exposes an audio output; the track then observes room
  # audio once a tap exists.
  @spec prepare_room(map(), map(), nil | map()) :: {:ok, [map()]} | {:error, map()}
  def prepare_room(captured, connections, mixer_resource \\ nil) do
    # Without a permitted interval there is nothing to tap; the room track
    # stays silent through the normal empty-track path.
    if Inventory.room_target?(captured.inventory.recording_targets) and
         captured.candidate.snapshot.effective.record_audio do
      listeners =
        Enum.filter(connections, fn {_id, graph} ->
          Enum.any?(graph.resources, &(&1.kind == :audio_output))
        end)

      Enum.reduce_while(listeners, {:ok, []}, fn {_id, graph}, {:ok, outputs} ->
        with [native] <- Enum.filter(graph.resources, &(&1.kind == :audio_output)),
             {:ok, binding} <-
               prepare_binding(native, graph.identity, captured, mixer_resource) do
          dependencies = Map.get(binding, :resources, [binding.resource])
          {:cont, {:ok, outputs ++ dependencies}}
        else
          _unavailable ->
            {:halt, ResourceQuery.failure(:recording, :room, :output_track_unavailable)}
        end
      end)
    else
      {:ok, []}
    end
  end

  defp prepare_agent(agent, captured, connections, mixer_resource) do
    policy = captured.candidate.snapshot

    listeners =
      Enum.filter(connections, fn {_id, graph} ->
        recipient = graph.identity.participant_id

        agent != recipient and
          Effective.audio_route_permitted?(policy.effective, agent, recipient)
      end)

    if listeners == [] do
      failure(agent)
    else
      Enum.reduce_while(listeners, {:ok, []}, fn {_id, graph}, {:ok, bindings} ->
        with [native] <- Enum.filter(graph.resources, &(&1.kind == :audio_output)),
             {:ok, binding} <-
               prepare_binding(native, graph.identity, captured, mixer_resource) do
          {:cont, {:ok, [binding | bindings]}}
        else
          _unavailable -> {:halt, failure(agent)}
        end
      end)
    end
  end

  defp prepare_binding(native, identity, captured, nil),
    do:
      EgressReadiness.prepare(
        native,
        identity,
        captured.room.room_mixer,
        captured.candidate.snapshot
      )

  defp prepare_binding(native, identity, captured, mixer_resource),
    do:
      EgressReadiness.prepare_candidate(
        native,
        identity,
        captured.room.room_mixer,
        captured.candidate,
        mixer_resource
      )

  defp failure(agent),
    do: ResourceQuery.failure(:recording_output, {:participant, agent}, :output_track_unavailable)
end
