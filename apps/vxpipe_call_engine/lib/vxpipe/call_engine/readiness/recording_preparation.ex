defmodule Vxpipe.CallEngine.Readiness.RecordingPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.{Inventory, RecordingOutputs, ResourceQuery}
  alias Vxpipe.CallEngine.RoomRecording

  def prepare(captured, connections) do
    case Map.fetch(captured.room, :recording) do
      :error -> {:ok, [], []}
      {:ok, recording} -> prepare_recording(recording, captured, connections)
    end
  end

  defp prepare_recording(recording, captured, connections) do
    policy = captured.candidate.snapshot

    with {:ok, _resource} <- ResourceQuery.observe(:recording, :room, recording, policy),
         :ok <- installed_recording_sources(captured),
         {:ok, agent_tracks, outputs} <- RecordingOutputs.prepare(captured, connections),
         {:ok, tracks} <- tracks(captured, connections, agent_tracks),
         :ok <-
           RoomRecording.prepare_tracks(recording, tracks, Snapshot.interval(policy, :recording)),
         {:ok, [resource | _dependencies] = resources} <-
           RoomRecording.readiness_resources(recording),
         {:ok, ^resource} <- ResourceQuery.observe(:recording, :room, recording, policy) do
      {:ok, tracks, resources ++ outputs}
    else
      {:error, %{kind: _kind}} = failure -> failure
      _unavailable -> ResourceQuery.failure(:recording, :room, :preparation_failed)
    end
  end

  defp installed_recording_sources(captured) do
    binding = captured.binding
    attempt_id = if binding.attempt, do: binding.attempt.id

    with {:ok, installed} <-
           Inventory.build(
             binding.plan,
             captured.candidate.base_snapshot,
             binding.connections,
             Keyword.put(binding.options, :attempt_id, attempt_id)
           ),
         true <-
           installed.recording_participant_ids == captured.inventory.recording_participant_ids do
      :ok
    else
      # The installed track preparer mutates live writers. Future sources require their own lease.
      _unprepared -> ResourceQuery.failure(:recording, :room, :policy_not_prepared)
    end
  end

  defp tracks(captured, connections, agent_tracks) do
    selected =
      for {:individual_tracks, ids} <- captured.inventory.recording_targets,
          id <- ids,
          into: MapSet.new(),
          do: id

    required = MapSet.intersection(selected, captured.inventory.recording_participant_ids)

    bound =
      connections
      |> MapSet.new(fn {_id, graph} -> graph.identity.participant_id end)
      |> MapSet.union(MapSet.new(Map.keys(agent_tracks)))

    if MapSet.subset?(required, bound) do
      tracks =
        for {id, graph} <- connections,
            MapSet.member?(required, graph.identity.participant_id),
            graph.input_track != nil,
            do: {:individual_track, graph.identity.participant_id, id, graph.input_track.track_id}

      output_tracks =
        agent_tracks
        |> Map.take(MapSet.to_list(required))
        |> Map.values()
        |> List.flatten()

      {:ok, Enum.sort(tracks ++ output_tracks)}
    else
      # Every selected source needs a prepared input or an authorized output recording track.
      ResourceQuery.failure(:recording, :room, :output_track_unavailable)
    end
  end
end
