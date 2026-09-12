defmodule Vxpipe.Persistence.CallDetailsSourceProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy
  alias Vxpipe.Calls.{CallDetailsAssessment, CallDetailsSource, PreparedCall}

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

    with {:ok, usage} <-
           CallDetailsUsageProjection.project(read.usage_observations, read.usage_amounts),
         {:ok, components} <- CallDetailsComponentProjection.project(read, recording),
         {:ok, source} <-
           CallDetailsSource.new(
             call: CallDetailsCallProjection.call(read.call),
             participants: CallDetailsCallProjection.participants(read),
             transcript: fact_sections.transcript,
             tools: fact_sections.tools,
             transfers: fact_sections.transfers,
             usage: usage,
             variables: CallDetailsVariablesProjection.project(read.variable_snapshots),
             artifacts: CallDetailsArtifactProjection.project(artifacts)
           ) do
      CallDetailsAssessment.new(read.call.ended_at, source, components)
    end
  end

  defp permitted_artifacts(%CallDetailsSourceRead{
         call: %PreparedCall{
           plan: %ResolvedCallPlan{media_policy: %MediaPolicy{record_audio: false}}
         }
       }),
       do: []

  defp permitted_artifacts(read), do: read.artifacts
end
