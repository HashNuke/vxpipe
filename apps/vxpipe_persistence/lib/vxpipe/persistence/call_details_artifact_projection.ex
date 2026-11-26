defmodule Vxpipe.Persistence.CallDetailsArtifactProjection do
  @moduledoc false

  alias Vxpipe.Calls.CallArtifact

  @spec project([CallArtifact.t()]) :: [map()]
  def project(artifacts) when is_list(artifacts), do: Enum.map(artifacts, &artifact/1)

  defp artifact(%CallArtifact{} = artifact) do
    %{
      "id" => artifact.id,
      "kind" => Atom.to_string(artifact.kind),
      "track_name" => CallArtifact.track_name(artifact),
      "reconnection" => artifact.reconnection,
      "participant_id" => artifact.participant_id,
      "connection_id" => artifact.connection_id,
      "track_id" => artifact.track_id,
      "object_key" => artifact.object_key,
      "object_reference" => artifact.object_reference,
      "sample_rate" => artifact.sample_rate,
      "channels" => artifact.channels,
      "sample_format" => Atom.to_string(artifact.sample_format),
      "started_offset_samples" => artifact.started_offset_samples,
      "ended_offset_samples" => artifact.ended_offset_samples,
      "sample_count" => artifact.sample_count,
      "accepted_chunks" => artifact.accepted_chunks,
      "rejected_chunks" => artifact.rejected_chunks,
      "gaps" => artifact.gaps,
      "status" => Atom.to_string(artifact.status),
      "terminal_reason" => artifact.terminal_reason,
      "duplicate_frames" => Map.get(artifact, :duplicate_frames, 0) || 0,
      "selected_connection_ids" => Map.get(artifact, :selected_connection_ids, []) || []
    }
    |> compact()
    |> Map.put("participant_key", artifact.participant_key)
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
