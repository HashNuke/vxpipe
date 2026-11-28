defmodule Vxpipe.Persistence.CallDetailsSourceProjection do
  @moduledoc false

  alias Vxpipe.Calls.{CallDetailsAssessment, CallDetailsSource, CallRecordingStatus}

  alias Vxpipe.Persistence.{
    CallDetailsArtifactProjection,
    CallDetailsCallProjection,
    CallDetailsComponentProjection,
    CallDetailsFactProjection,
    CallDetailsSourceRead,
    CallDetailsUsageProjection,
    CallDetailsVariablesProjection
  }

  @spec project(CallDetailsSourceRead.t(), :configured | :unconfigured) ::
          {:ok, CallDetailsAssessment.t()} | {:error, term()}
  def project(%CallDetailsSourceRead{} = read, recording) do
    fact_sections = CallDetailsFactProjection.sections(read.facts)
    artifacts = permitted_artifacts(read)
    call_map = call_with_recording(read, recording)

    with {:ok, usage} <-
           CallDetailsUsageProjection.project(read.usage_observations, read.usage_amounts),
         {:ok, components} <- CallDetailsComponentProjection.project(read, recording),
         {:ok, source} <-
           CallDetailsSource.new(
             call: call_map,
             participants: CallDetailsCallProjection.participants(read),
             transcript: fact_sections.transcript,
             tools: fact_sections.tools,
             transfers: fact_sections.transfers,
             decisions: fact_sections.decisions,
             usage: usage,
             variables: CallDetailsVariablesProjection.project(read.variable_snapshots),
             artifacts: CallDetailsArtifactProjection.project(artifacts)
           ) do
      CallDetailsAssessment.new(read.call.ended_at, source, components)
    end
  end

  defp call_with_recording(%CallDetailsSourceRead{} = read, recording) do
    base = CallDetailsCallProjection.call(read.call)

    status =
      CallRecordingStatus.status(read.facts, read.artifacts,
        fallback_requested: CallRecordingStatus.plan_recording(read.call.plan),
        fallback_configured: recording == :configured
      )

    Map.put(base, "recording", status)
  end

  defp permitted_artifacts(%CallDetailsSourceRead{} = read) do
    CallRecordingStatus.permitted_artifacts(
      read.facts,
      CallRecordingStatus.plan_recording(read.call.plan),
      read.artifacts
    )
  end
end
