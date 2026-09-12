defmodule Vxpipe.Persistence.CallDetailsComponentProjection do
  @moduledoc false

  alias Vxpipe.CallEngine.ResolvedCallPlan
  alias Vxpipe.CallEngine.ResolvedCallPlan.MediaPolicy
  alias Vxpipe.Calls.{ArchiveStatus, PublicationComponent, VariableSnapshotHistory}
  alias Vxpipe.Persistence.CallDetailsSourceRead

  @spec project(CallDetailsSourceRead.t(), :configured | :unconfigured) ::
          {:ok, [PublicationComponent.t()]}
  def project(%CallDetailsSourceRead{} = read, recording) do
    with {:ok, history} <- history(read.facts),
         {:ok, variables} <- variables(read.call.plan, read.variable_snapshots),
         {:ok, usage} <- usage(read.usage_observations, read.usage_amounts),
         {:ok, recording} <- recording(read.call.plan, read.artifacts, recording) do
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

  defp recording(
         %ResolvedCallPlan{media_policy: %MediaPolicy{record_audio: false}},
         artifacts,
         _configured
       ) do
    if Enum.any?(artifacts, &(&1.sample_count > 0)) do
      component("recording", :failed, %{"reason" => "prohibited_audio_present"})
    else
      component("recording", :prohibited, %{"policy" => "record_audio_disabled"})
    end
  end

  defp recording(_plan, [], :configured), do: component("recording", :pending)
  defp recording(_plan, [], :unconfigured), do: component("recording", :unconfigured)

  defp recording(_plan, artifacts, _configured) do
    incomplete = Enum.count(artifacts, &(&1.status == :incomplete))

    if incomplete == 0 do
      component("recording", :complete, %{"artifact_count" => length(artifacts)})
    else
      component("recording", :failed, %{
        "artifact_count" => length(artifacts),
        "incomplete_artifact_count" => incomplete
      })
    end
  end

  defp contiguous?([]), do: false

  defp contiguous?(revisions) do
    revisions == Enum.to_list(0..List.last(revisions))
  end

  defp component(name, status, details \\ %{}) do
    PublicationComponent.new(name, status, details)
  end
end
