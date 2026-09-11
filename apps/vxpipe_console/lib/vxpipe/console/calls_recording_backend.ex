defmodule Vxpipe.Console.CallsRecordingBackend do
  @moduledoc false

  @behaviour Vxpipe.Console.CallRecordingBackend

  alias Vxpipe.Artifacts.S3ObjectReader
  alias Vxpipe.Calls

  alias Vxpipe.Console.{RecordingConfiguration, RecordingWave}
  alias Vxpipe.Console.CallRecording.{ArtifactReader, Source, Summary}

  @impl true
  def list(options, principal, call_id) when is_list(options) do
    case Calls.fetch_call_artifacts(principal, call_id, calls_options(options)) do
      {:ok, artifacts} ->
        reader_binding = reader_binding(options)

        summaries =
          artifacts
          |> Enum.map(&Summary.new(&1, playable?(&1, reader_binding)))
          |> Enum.sort_by(&sort_key/1)

        {:ok, summaries}

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def open(options, principal, call_id, artifact_id) when is_list(options) do
    with {:ok, artifact} <-
           Calls.fetch_call_artifact(
             principal,
             call_id,
             artifact_id,
             calls_options(options)
           ),
         {:ok, reader_binding} <- reader_binding(options) do
      source(artifact, reader_binding)
    end
  end

  defp source(artifact, {object_reader, reader_options}) do
    with {:ok, reader} <-
           ArtifactReader.new(artifact.object_reference, object_reader, reader_options) do
      Source.new(artifact, reader)
    end
  end

  defp playable?(artifact, {:ok, reader_binding}) do
    with {:ok, source} <- source(artifact, reader_binding),
         {:ok, _wave} <- RecordingWave.new(source) do
      true
    else
      _unavailable -> false
    end
  end

  defp playable?(_artifact, {:error, _reason}), do: false

  defp reader_binding(options) do
    with {:ok, reader_options} <-
           RecordingConfiguration.playback(recording_settings(options)) do
      {:ok,
       {Keyword.get(options, :object_reader, S3ObjectReader),
        Keyword.merge(reader_options, Keyword.get(options, :object_reader_options, []))}}
    end
  end

  defp calls_options(options), do: Keyword.get(options, :calls_options, [])

  defp sort_key(%Summary{kind: :full_mix, id: id}), do: {0, "", "", "", id}

  defp sort_key(%Summary{} = summary) do
    {1, summary.participant_id, summary.connection_id, summary.track_id, summary.id}
  end

  defp recording_settings(options) do
    Keyword.get_lazy(options, :recording_settings, fn ->
      Application.fetch_env!(:vxpipe_console, :recording)
    end)
  end
end
