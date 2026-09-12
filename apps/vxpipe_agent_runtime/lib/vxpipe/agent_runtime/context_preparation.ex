defmodule Vxpipe.AgentRuntime.ContextPreparation do
  @moduledoc "Prepares one measured model context, with at most one compaction attempt."

  alias Vxpipe.AgentRuntime.Conversation.Entry

  alias Vxpipe.AgentRuntime.{
    CompactionRequest,
    CompactionRunner,
    ContextBudget,
    Conversation,
    ConversationCompaction,
    ConversationCompactionSnapshot,
    ModelRequest,
    PreparedContext,
    RequestBudget
  }

  @type preparation_error ::
          :compacted_context_too_large
          | :context_compaction_unavailable
          | :input_token_count_unavailable
          | :invalid_compaction_context
          | :protected_context_too_large

  @spec prepare(Conversation.t(), ModelRequest.t(), map()) ::
          {:ok, PreparedContext.t()} | {:error, preparation_error()}
  def prepare(%Conversation{} = conversation, %ModelRequest{} = request, config)
      when is_map(config) do
    with {:ok, staged_messages} <- staged_messages(conversation, request),
         {:ok, measured} <- assess(request, config) do
      case measured.decision do
        :within_budget ->
          {:ok,
           %PreparedContext{
             conversation: conversation,
             request: request,
             input_tokens: measured.input_tokens,
             compaction: nil
           }}

        {:compact, _target} ->
          compact(conversation, staged_messages, request, config)
      end
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _invalid -> {:error, :invalid_compaction_context}
    end
  end

  def prepare(%Conversation{}, %ModelRequest{}, _config),
    do: {:error, :invalid_compaction_context}

  defp compact(conversation, staged_messages, request, config) do
    pending_invocation_ids = Enum.map(request.pending_invocations, & &1.invocation_id)

    with {:ok, snapshot} <-
           ConversationCompaction.snapshot(conversation, pending_invocation_ids,
             recent_entries: Map.fetch!(config, :recent_entries)
           ),
         protected_request <- protected_request(snapshot, staged_messages, request),
         {:ok, protected} <- assess(protected_request, config),
         {:ok, maximum_summary_tokens, required_maximum} <-
           summary_limits(Map.fetch!(config, :budget), protected.input_tokens),
         {:ok, compaction_request} <-
           compaction_request(snapshot, maximum_summary_tokens, request.correlation),
         {:ok, result} <-
           CompactionRunner.run(
             Map.fetch!(config, :compactor),
             compaction_request,
             Map.fetch!(config, :compactor_timeout_ms)
           ),
         {:ok, compacted_conversation} <-
           ConversationCompaction.apply(conversation, snapshot, result.summary),
         compacted_request <-
           ModelRequest.with_messages(
             request,
             compacted_conversation.messages ++ staged_messages
           ),
         {:ok, compacted} <- assess(compacted_request, config),
         true <- compacted.input_tokens <= required_maximum do
      {:ok,
       %PreparedContext{
         conversation: compacted_conversation,
         request: compacted_request,
         input_tokens: compacted.input_tokens,
         compaction: result
       }}
    else
      {:error, :no_compactable_history} -> {:error, :protected_context_too_large}
      {:error, :invalid_compaction_options} -> {:error, :invalid_compaction_context}
      {:error, :invalid_compaction_request} -> {:error, :invalid_compaction_context}
      {:error, :stale_compaction_snapshot} -> {:error, :invalid_compaction_context}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      false -> {:error, :compacted_context_too_large}
      _invalid -> {:error, :invalid_compaction_context}
    end
  rescue
    _error -> {:error, :invalid_compaction_context}
  end

  defp staged_messages(conversation, request) do
    {committed, staged} = Enum.split(request.messages, conversation.size)

    if committed == conversation.messages do
      {:ok, staged}
    else
      {:error, :invalid_compaction_context}
    end
  end

  defp protected_request(snapshot, staged_messages, request) do
    messages =
      snapshot
      |> ConversationCompactionSnapshot.retained_entries()
      |> Enum.flat_map(& &1.messages)

    ModelRequest.with_messages(request, messages ++ staged_messages)
  end

  defp compaction_request(snapshot, maximum_summary_tokens, correlation) do
    messages = Enum.flat_map(snapshot.selected_entries, & &1.messages)
    source_correlations = Enum.flat_map(snapshot.selected_entries, &Entry.source_correlations/1)

    CompactionRequest.new(messages, maximum_summary_tokens, correlation, source_correlations)
  end

  defp summary_limits(%ContextBudget{} = budget, protected_input_tokens) do
    safe_allowance = budget.usable_input_tokens - protected_input_tokens

    if safe_allowance <= 0 do
      {:error, :protected_context_too_large}
    else
      target_allowance = budget.target_input_tokens - protected_input_tokens

      if target_allowance > 0 do
        {:ok, target_allowance, budget.target_input_tokens}
      else
        {:ok, safe_allowance, budget.usable_input_tokens}
      end
    end
  end

  defp assess(request, config) do
    RequestBudget.assess(
      request,
      Map.fetch!(config, :budget),
      Map.fetch!(config, :input_token_counter),
      timeout_ms: Map.fetch!(config, :input_token_timeout_ms)
    )
  rescue
    _error -> {:error, :invalid_compaction_context}
  end
end
