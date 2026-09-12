defmodule Vxpipe.Persistence.CallDetailsVariablesProjection do
  @moduledoc false

  alias Vxpipe.Calls.{VariableSnapshot, VariableSnapshotHistory}
  alias Vxpipe.Persistence.CallDetailsTimestamp

  @spec project(VariableSnapshotHistory.t()) :: map()
  def project(%VariableSnapshotHistory{} = history) do
    %{
      "latest_revision" => latest_revision(history.latest),
      "sections" => latest_sections(history.latest),
      "history" => Enum.map(history.snapshots, &snapshot/1)
    }
  end

  defp snapshot(%VariableSnapshot{} = snapshot) do
    compact(%{
      "id" => snapshot.id,
      "kind" => Atom.to_string(snapshot.kind),
      "revision" => snapshot.global_revision,
      "section" => snapshot.section,
      "section_revision" => snapshot.section_revision,
      "occurred_at" => CallDetailsTimestamp.format(snapshot.occurred_at),
      "participant_id" => snapshot.participant_id,
      "activation_id" => snapshot.activation_id,
      "source_participant_id" => snapshot.source_participant_id,
      "command_id" => snapshot.command_id,
      "correlation_id" => snapshot.correlation_id,
      "tool_call_id" => snapshot.tool_call_id,
      "source_policy" => snapshot.source_policy,
      "sections" => section_documents(snapshot.sections)
    })
  end

  defp latest_revision(nil), do: nil
  defp latest_revision(snapshot), do: snapshot.global_revision

  defp latest_sections(nil), do: %{}

  defp latest_sections(snapshot) do
    Map.new(snapshot.sections, fn {name, section} -> {name, section.value} end)
  end

  defp section_documents(sections) do
    Map.new(sections, fn {name, section} ->
      {name, %{"revision" => section.revision, "value" => section.value}}
    end)
  end

  defp compact(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
