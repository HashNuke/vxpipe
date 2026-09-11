defmodule Vxpipe.Console.TestCallRecordingArtifactRepository do
  @moduledoc false

  @behaviour Vxpipe.Calls.ArtifactRepository

  @impl true
  def store_call_artifact(_context, artifact), do: {:ok, artifact}

  @impl true
  def fetch_call_artifacts({observer, response}, tenant_key, call_id) do
    send(observer, {:fetch_call_recording_artifacts, tenant_key, call_id})
    response
  end

  @impl true
  def fetch_call_artifact({observer, response}, tenant_key, call_id, artifact_id) do
    send(observer, {:fetch_call_recording_artifact, tenant_key, call_id, artifact_id})
    response
  end
end
