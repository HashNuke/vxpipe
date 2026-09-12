defmodule Vxpipe.AgentRuntime.ConversationCompaction do
  @moduledoc "Selects and atomically replaces compactable conversation entries."

  alias Vxpipe.AgentRuntime.Conversation
  alias Vxpipe.AgentRuntime.Conversation.Entry
  alias Vxpipe.AgentRuntime.{ConversationCompactionSnapshot, Message}

  @spec snapshot(Conversation.t(), [String.t()], keyword()) ::
          {:ok, ConversationCompactionSnapshot.t()}
          | {:error, :invalid_compaction_options | :no_compactable_history}
  def snapshot(conversation, pending_invocation_ids, options \\ [])

  def snapshot(%Conversation{} = conversation, pending_invocation_ids, options)
      when is_list(pending_invocation_ids) and is_list(options) do
    with true <- Enum.all?(pending_invocation_ids, &is_binary/1),
         {:ok, options} <- Keyword.validate(options, recent_entries: 4),
         recent_entries when is_integer(recent_entries) and recent_entries > 0 <-
           Keyword.fetch!(options, :recent_entries),
         {:ok, snapshot} <-
           select(conversation.entries, MapSet.new(pending_invocation_ids), recent_entries) do
      {:ok, snapshot}
    else
      {:error, :no_compactable_history} = error -> error
      _invalid -> {:error, :invalid_compaction_options}
    end
  end

  def snapshot(_conversation, _pending_invocation_ids, _options),
    do: {:error, :invalid_compaction_options}

  @spec apply(Conversation.t(), ConversationCompactionSnapshot.t(), String.t()) ::
          {:ok, Conversation.t()}
          | {:error, :invalid_summary | :stale_compaction_snapshot}
  def apply(%Conversation{} = current, %ConversationCompactionSnapshot{} = snapshot, summary)
      when is_binary(summary) do
    if String.valid?(summary) and String.trim(summary) != "" do
      apply_if_current(current, snapshot, summary)
    else
      {:error, :invalid_summary}
    end
  end

  def apply(%Conversation{}, %ConversationCompactionSnapshot{}, _summary),
    do: {:error, :invalid_summary}

  defp select(entries, pending_invocation_ids, recent_entries) do
    indexed = Enum.with_index(entries)

    recent_indices =
      indexed
      |> Enum.reject(fn {entry, _index} -> entry.retention == :permanent end)
      |> Enum.take(-recent_entries)
      |> Enum.map(fn {_entry, index} -> index end)
      |> MapSet.new()

    {leading, remaining} =
      Enum.split_while(indexed, fn {entry, _index} -> entry.retention == :permanent end)

    {selected, trailing} =
      Enum.split_while(remaining, fn {entry, index} ->
        entry.retention != :permanent and not MapSet.member?(recent_indices, index) and
          not pending_entry?(entry, pending_invocation_ids)
      end)

    selected_entries = unindex(selected)

    if selected_entries == [] do
      {:error, :no_compactable_history}
    else
      {:ok,
       %ConversationCompactionSnapshot{
         base_entries: entries,
         leading_entries: unindex(leading),
         selected_entries: selected_entries,
         trailing_entries: unindex(trailing)
       }}
    end
  end

  defp pending_entry?(entry, pending_invocation_ids) do
    Enum.any?(entry.messages, fn message ->
      MapSet.member?(pending_invocation_ids, message.tool_call_id) or
        Enum.any?(message.tool_calls, &MapSet.member?(pending_invocation_ids, &1.id))
    end)
  end

  defp apply_if_current(current, snapshot, summary) do
    base_count = length(snapshot.base_entries)
    {current_base, appended_entries} = Enum.split(current.entries, base_count)

    if current_base == snapshot.base_entries do
      durable_correlations =
        Enum.flat_map(snapshot.selected_entries, &Entry.durable_correlations/1)

      source_correlations =
        Enum.flat_map(snapshot.selected_entries, &Entry.source_correlations/1)

      summary_entry =
        Entry.summary([Message.summary(summary)], source_correlations, durable_correlations)

      entries =
        snapshot.leading_entries ++
          [summary_entry] ++ snapshot.trailing_entries ++ appended_entries

      {:ok, Conversation.from_entries(entries)}
    else
      {:error, :stale_compaction_snapshot}
    end
  end

  defp unindex(entries), do: Enum.map(entries, fn {entry, _index} -> entry end)
end
