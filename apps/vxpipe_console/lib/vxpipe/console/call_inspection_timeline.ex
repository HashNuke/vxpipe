defmodule Vxpipe.Console.CallInspectionTimeline do
  @moduledoc false

  alias Vxpipe.Calls.{CallDetailPage, CallTimelineEntry, LiveCallInspection}

  @spec combine(CallDetailPage.t() | nil, LiveCallInspection.t() | nil) ::
          [CallTimelineEntry.t()]
  def combine(persisted, live) do
    persisted_entries(persisted)
    |> Kernel.++(live_entries(live))
    |> Enum.uniq_by(&selection_key/1)
    |> Enum.sort_by(&sort_key/1, :desc)
  end

  @spec select([CallTimelineEntry.t()], String.t() | nil) :: CallTimelineEntry.t() | nil
  def select(entries, nil), do: List.first(entries)

  def select(entries, selection_key) when is_binary(selection_key) do
    Enum.find(entries, &(selection_key(&1) == selection_key)) || List.first(entries)
  end

  @spec selection_key(CallTimelineEntry.t()) :: String.t()
  def selection_key(%CallTimelineEntry{} = entry), do: "#{entry.source}:#{entry.id}"

  defp persisted_entries(%CallDetailPage{timeline: entries}), do: entries
  defp persisted_entries(nil), do: []

  defp live_entries(%LiveCallInspection{timeline: entries}), do: entries
  defp live_entries(nil), do: []

  defp sort_key(entry) do
    {
      DateTime.to_unix(entry.occurred_at, :microsecond),
      source_rank(entry.source),
      entry.source_sequence || entry.variable_revision || 0,
      entry.id
    }
  end

  defp source_rank(:live), do: 1
  defp source_rank(:persisted), do: 0
end
