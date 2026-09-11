defmodule Vxpipe.Console.CallsRecordingBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecordingBackend

  alias Vxpipe.Artifacts.S3ObjectReader
  alias Vxpipe.Calls

  alias Vxpipe.Console.{RecordingConfiguration}
  alias Vxpipe.Console.CallRecording.{ArtifactReader, Source}

  @impl true
  def open(options, principal, call_id, artifact_id) when is_list(options) do
    with {:ok, artifact} <-
           Calls.fetch_call_artifact(
             principal,
             call_id,
             artifact_id,
             Keyword.get(options, :calls_options, [])
           ),
         {:ok, reader_options} <-
           RecordingConfiguration.playback(recording_settings(options)),
         {:ok, reader} <-
           ArtifactReader.new(
             artifact.object_reference,
             Keyword.get(options, :object_reader, S3ObjectReader),
             Keyword.merge(reader_options, Keyword.get(options, :object_reader_options, []))
           ) do
      Source.new(artifact, reader)
    end
  end

  defp recording_settings(options) do
    Keyword.get_lazy(options, :recording_settings, fn ->
      Application.fetch_env!(:vxpipe_console, :recording)
    end)
  end
end
