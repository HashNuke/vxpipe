defmodule Vxpipe.Artifacts.RecordingWriter do
  @moduledoc "Adapts the call engine's non-blocking recording port to bounded artifact writers."

  @behaviour Vxpipe.CallEngine.Recording.Writer

  alias Vxpipe.Artifacts.{ArtifactSpec, Handoff, RecordingLocator, Writer, Writers}
  alias Vxpipe.Artifacts.RecordingWriter.Handle
  alias Vxpipe.CallEngine.Recording.{Chunk, Stream}

  @impl true
  def open(%Stream{} = stream, options) when is_list(options) do
    with source when is_pid(source) <- Keyword.get(options, :source),
         {:ok, spec} <- stream |> RecordingLocator.specification() |> ArtifactSpec.new(),
         {:ok, writer} <- Writers.start_writer(Keyword.put(options, :spec, spec)) do
      {:ok,
       %Handle{
         writer: writer,
         handoff: Writer.handoff(writer),
         channels: stream.channels
       }}
    else
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_recording_writer_options}
    end
  end

  def open(_stream, _options), do: {:error, :invalid_recording_writer_options}

  @impl true
  def readiness(%Handle{} = handle), do: Writer.readiness(handle.writer)

  @impl true
  def offer(%Handle{} = handle, %Chunk{} = chunk) do
    artifact_chunk = %Vxpipe.Artifacts.Chunk{
      sequence: chunk.sequence,
      offset_samples: chunk.offset_samples,
      sample_count: chunk.sample_count,
      channels: handle.channels,
      timestamp: chunk.timestamp,
      policy_revision: chunk.policy_revision,
      source_participant_ids: chunk.source_participant_ids,
      payload: chunk.payload
    }

    Handoff.offer(handle.handoff, artifact_chunk)
  end

  def offer(%Handle{}, _chunk), do: {:error, :invalid_chunk}
end
