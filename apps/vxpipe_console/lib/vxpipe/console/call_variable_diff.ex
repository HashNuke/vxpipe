defmodule Vxpipe.Console.CallVariableDiff do
  @moduledoc false

  alias Vxpipe.Calls.{CallDetailPage, CallTimelineEntry, LiveCallInspection}

  @enforce_keys [:from_revision, :to_revision, :changes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          from_revision: non_neg_integer(),
          to_revision: non_neg_integer(),
          changes: map()
        }

  @spec between(CallDetailPage.t() | nil, LiveCallInspection.t() | nil) ::
          {:ok, t()} | :unavailable
  def between(%CallDetailPage{} = persisted, %LiveCallInspection{} = live) do
    with %CallTimelineEntry{} = before <- latest_snapshot(persisted.timeline),
         %CallTimelineEntry{} = after_snapshot <- latest_snapshot(live.timeline),
         true <- before.variable_revision != after_snapshot.variable_revision do
      {:ok,
       %__MODULE__{
         from_revision: before.variable_revision,
         to_revision: after_snapshot.variable_revision,
         changes: section_changes(before.payload, after_snapshot.payload)
       }}
    else
      _missing_or_same_revision -> :unavailable
    end
  end

  def between(_persisted, _live), do: :unavailable

  defp latest_snapshot(entries) do
    entries
    |> Enum.filter(&variable_snapshot?/1)
    |> Enum.max_by(& &1.variable_revision, fn -> nil end)
  end

  defp variable_snapshot?(%CallTimelineEntry{
         kind: :variable_snapshot,
         variable_revision: revision,
         payload: payload
       }),
       do: is_integer(revision) and revision >= 0 and is_map(payload)

  defp variable_snapshot?(_entry), do: false

  defp section_changes(before, after_snapshot) do
    before
    |> Map.keys()
    |> Kernel.++(Map.keys(after_snapshot))
    |> Enum.uniq()
    |> Enum.sort()
    |> Map.new(fn section ->
      before_value = section_value(Map.get(before, section))
      after_value = section_value(Map.get(after_snapshot, section))

      {section, field_changes(before_value, after_value)}
    end)
    |> Map.reject(fn {_section, changes} -> map_size(changes) == 0 end)
  end

  defp section_value(%{"value" => value}) when is_map(value), do: value
  defp section_value(%{value: value}) when is_map(value), do: value
  defp section_value(_section), do: %{}

  defp field_changes(before, after_snapshot) do
    before
    |> Map.keys()
    |> Kernel.++(Map.keys(after_snapshot))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn field, changes ->
      before_value = Map.get(before, field)
      after_value = Map.get(after_snapshot, field)

      if before_value == after_value do
        changes
      else
        Map.put(changes, field, %{"before" => before_value, "after" => after_value})
      end
    end)
  end
end
