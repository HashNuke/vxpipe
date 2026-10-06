defmodule Vxpipe.Persistence.EctoStorage do
  @moduledoc "Projects private engine archive facts through Calls-owned workflows."

  @behaviour Vxpipe.CallEngine.Archive.Writer
  @behaviour Vxpipe.Artifacts.Metadata.Writer

  alias Vxpipe.Artifacts.Result, as: ArtifactResult
  alias Vxpipe.CallEngine.CallVariables.{BaselineSnapshot, UpdateSnapshot}
  alias Vxpipe.CallEngine.Archive.Fact, as: EngineFact
  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallFact, EngineArchiveProjection, UsageObservationProjection}
  alias Vxpipe.Persistence.ArtifactResultProjection

  @terminal_errors [
    :ambiguous_cumulative_order,
    :call_incarnation_mismatch,
    :call_fact_conflict,
    :call_fact_insert_failed,
    :call_fact_sequence_conflict,
    :call_end_conflict,
    :outgoing_lifecycle_conflict,
    :call_artifact_conflict,
    :call_artifact_insert_failed,
    :call_not_found,
    :call_not_started,
    :conflicting_delivery,
    :invalid_variable_snapshot,
    :invalid_usage_amount,
    :invalid_usage_observation,
    :invalid_usage_observation_fact,
    :mixed_calls,
    :mixed_measurement_modes,
    :usage_amount_delete_failed,
    :usage_amount_insert_failed,
    :usage_observation_conflict,
    :usage_observation_insert_failed,
    :invalid_call_artifact,
    :invalid_call_fact,
    :variable_snapshot_conflict,
    :variable_snapshot_revision_conflict
  ]

  @impl true
  def write(options, %BaselineSnapshot{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store(options)
  end

  def write(options, %UpdateSnapshot{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store(options)
  end

  def write(options, %EngineFact{} = fact) when is_list(options) do
    fact
    |> EngineArchiveProjection.project()
    |> store_call_fact(options)
  end

  def write(_options, _unsupported), do: {:discard, :unsupported_archive_fact}

  @impl Vxpipe.Artifacts.Metadata.Writer
  def store_metadata(options, %ArtifactResult{} = result) when is_list(options) do
    result
    |> ArtifactResultProjection.project()
    |> store_call_artifact(options)
  end

  defp store({:ok, snapshot}, options) do
    case Calls.archive_variable_snapshot(snapshot, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store({:error, reason}, _options), do: {:discard, reason}

  defp store_call_fact({:ok, fact}, options) do
    case archive_and_project_usage(fact, options) do
      :ok -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store_call_fact({:error, reason}, _options), do: {:discard, reason}

  defp archive_and_project_usage(fact, options) do
    with {:ok, archived} <- Calls.archive_call_fact(fact, options),
         :ok <- project_usage(archived, options) do
      :ok
    end
  end

  defp project_usage(%CallFact{kind: :usage_observed} = fact, options) do
    with {:ok, observation} <- UsageObservationProjection.project(fact),
         {:ok, _stored} <- Calls.store_usage_observation(observation, options) do
      :ok
    end
  end

  defp project_usage(%CallFact{}, _options), do: :ok

  defp store_call_artifact({:ok, artifact}, options) do
    case Calls.archive_call_artifact(artifact, options) do
      {:ok, _stored} -> :ok
      {:error, reason} when reason in @terminal_errors -> {:discard, reason}
      {:error, reason} -> {:retry, reason}
    end
  end

  defp store_call_artifact({:error, reason}, _options), do: {:discard, reason}
end
