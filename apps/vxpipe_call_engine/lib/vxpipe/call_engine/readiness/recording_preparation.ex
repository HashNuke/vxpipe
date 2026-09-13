defmodule Vxpipe.CallEngine.Readiness.RecordingPreparation do
  @moduledoc false

  alias Vxpipe.CallEngine.MediaPolicy.Snapshot
  alias Vxpipe.CallEngine.Readiness.ResourceQuery
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
         {:ok, tracks} <- tracks(captured, connections),
         :ok <-
           RoomRecording.prepare_tracks(recording, tracks, Snapshot.interval(policy, :recording)),
         {:ok, [resource | _dependencies] = resources} <-
           RoomRecording.readiness_resources(recording),
         {:ok, ^resource} <- ResourceQuery.observe(:recording, :room, recording, policy) do
      {:ok, tracks, resources}
    else
      {:error, %{kind: _kind}} = failure -> failure
      _unavailable -> ResourceQuery.failure(:recording, :room, :preparation_failed)
    end
  end

  defp tracks(captured, connections) do
    selected =
      for {:individual_tracks, ids} <- captured.inventory.recording_targets,
          id <- ids,
          into: MapSet.new(),
          do: id

    required = MapSet.intersection(selected, captured.inventory.recording_participant_ids)
    bound = MapSet.new(connections, fn {_id, graph} -> graph.identity.participant_id end)

    if MapSet.subset?(required, bound) do
      tracks =
        for {id, graph} <- connections,
            MapSet.member?(required, graph.identity.participant_id),
            graph.input_track != nil,
            do: {:individual_track, graph.identity.participant_id, id, graph.input_track.track_id}

      {:ok, Enum.sort(tracks)}
    else
      # Agent speech uses the receiving output's recording track, not its own microphone.
      ResourceQuery.failure(:recording, :room, :output_track_unavailable)
    end
  end
end
