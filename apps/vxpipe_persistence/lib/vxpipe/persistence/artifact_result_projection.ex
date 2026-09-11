defmodule Vxpipe.Persistence.ArtifactResultProjection do
  @moduledoc false

  alias Vxpipe.Artifacts.{Manifest, Result}
  alias Vxpipe.Calls.CallArtifact

  @spec project(Result.t()) :: {:ok, CallArtifact.t()} | {:error, :invalid_call_artifact}
  def project(%Result{manifest: %Manifest{} = manifest, artifact: stored}) do
    with {:ok, object_reference} <- object_reference(stored, manifest.object_key) do
      CallArtifact.new(
        id: manifest.artifact_id,
        tenant_key: manifest.tenant_id,
        call_id: manifest.call_id,
        room_id: manifest.room_id,
        incarnation_id: manifest.incarnation_id,
        kind: manifest.kind,
        participant_id: manifest.participant_id,
        connection_id: manifest.connection_id,
        track_id: manifest.track_id,
        object_key: manifest.object_key,
        object_reference: object_reference,
        sample_rate: manifest.sample_rate,
        channels: manifest.channels,
        sample_format: manifest.sample_format,
        started_offset_samples: manifest.started_offset_samples,
        ended_offset_samples: manifest.ended_offset_samples,
        sample_count: manifest.sample_count,
        accepted_chunks: manifest.accepted_chunks,
        rejected_chunks: manifest.rejected_chunks,
        gaps: Enum.map(manifest.gaps, &gap/1),
        status: manifest.status,
        terminal_reason: terminal_reason(manifest.terminal_reason)
      )
    end
  end

  def project(_result), do: {:error, :invalid_call_artifact}

  defp object_reference(nil, _object_key), do: {:ok, nil}

  defp object_reference(stored, object_key) when is_map(stored) do
    stored_key = Map.get(stored, :object_key) || Map.get(stored, "object_key")
    etag = Map.get(stored, :etag) || Map.get(stored, "etag")

    if stored_key == object_key and (is_nil(etag) or is_binary(etag)) do
      {:ok, %{"object_key" => object_key, "etag" => etag}}
    else
      {:error, :invalid_call_artifact}
    end
  end

  defp object_reference(_stored, _object_key), do: {:error, :invalid_call_artifact}

  defp gap(%{offset_samples: offset, sample_count: count}) do
    %{"offset_samples" => offset, "sample_count" => count}
  end

  defp gap(other), do: other

  defp terminal_reason(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp terminal_reason({:shutdown, reason}) when is_atom(reason),
    do: "shutdown:" <> Atom.to_string(reason)

  defp terminal_reason(_reason), do: "other"
end
