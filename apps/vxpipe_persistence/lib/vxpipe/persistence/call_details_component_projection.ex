defmodule Vxpipe.Persistence.CallDetailsComponentProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan

  alias Vxpipe.Calls.{
    ArchiveStatus,
    CallRecordingStatus,
    PublicationComponent,
    VariableSnapshotHistory
  }

  alias Vxpipe.Persistence.CallDetailsSourceRead

  @spec project(CallDetailsSourceRead.t(), :configured | :unconfigured) ::
          {:ok, [PublicationComponent.t()]}
  def project(%CallDetailsSourceRead{} = read, recording) do
    with {:ok, history} <- history(read.facts),
         {:ok, variables} <- variables(read.call.plan, read.variable_snapshots),
         {:ok, usage} <- usage(read.usage_observations, read.usage_amounts),
         {:ok, recording} <- recording(read.facts, read.call.plan, read.artifacts, recording) do
      {:ok, [history, variables, usage, recording]}
    end
  end

  defp history(facts) do
    status = ArchiveStatus.from_facts(facts)

    details = %{
      "last_sequence" => status.last_sequence,
      "missing_sequence_count" => status.missing_sequence_count,
      "missing_sequences" => status.missing_sequences,
      "duplicate_id_count" => status.duplicate_id_count,
      "duplicate_sequence_count" => status.duplicate_sequence_count
    }

    component("history", if(status.complete?, do: :complete, else: :missing), details)
  end

  defp variables(%ResolvedCallPlan{} = plan, %VariableSnapshotHistory{} = history) do
    expected? = map_size(plan.call_variables.sections) > 0
    revisions = Enum.map(history.snapshots, & &1.global_revision)

    cond do
      history.snapshots == [] and not expected? ->
        component("variables", :not_produced)

      history.snapshots == [] ->
        component("variables", :missing, %{"reason" => "baseline_unavailable"})

      contiguous?(revisions) and not is_nil(history.latest) and
          history.latest.global_revision == List.last(revisions) ->
        component("variables", :complete, %{"latest_revision" => history.latest.global_revision})

      true ->
        component("variables", :missing, %{"persisted_revisions" => revisions})
    end
  end

  defp usage([], []), do: component("usage", :not_produced)

  defp usage(observations, amounts) do
    observation_ids = MapSet.new(observations, & &1.id)
    referenced_ids = amounts |> Enum.flat_map(& &1.observation_ids) |> MapSet.new()

    if MapSet.subset?(referenced_ids, observation_ids) do
      component("usage", :complete, %{
        "amount_count" => length(amounts),
        "observation_count" => length(observations)
      })
    else
      component("usage", :missing, %{
        "amount_count" => length(amounts),
        "observation_count" => length(observations)
      })
    end
  end

  defp recording(facts, plan, artifacts, configured) do
    {status, details} =
      CallRecordingStatus.component_decision(facts, artifacts,
        fallback_requested: CallRecordingStatus.plan_recording(plan),
        fallback_configured: configured == :configured
      )

    component("recording", status, details)
  end

  defp contiguous?([]), do: false

  defp contiguous?(revisions) do
    revisions == Enum.to_list(0..List.last(revisions))
  end

  defp component(name, status, details \\ %{}) do
    PublicationComponent.new(name, status, details)
  end
end
