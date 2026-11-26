defmodule Vxpipe.AgentRuntime.Conversation.WorkerCommit do
  @moduledoc false

  alias Vxpipe.AgentRuntime.Conversation

  # The runner commits each compaction separately, before generating, and each
  # tool exchange after submission. Advance the worker baseline on every
  # handoff, even when its compaction has lost a race with a playback receipt.
  def merge(current, previous_entries, worker) do
    case Enum.split(worker.entries, length(previous_entries)) do
      {^previous_entries, []} ->
        current

      {^previous_entries, appended} ->
        Conversation.from_entries(current.entries ++ appended, current.version + 1)

      _compaction when current.entries == previous_entries ->
        Conversation.from_entries(worker.entries, current.version + 1)

      _stale_compaction ->
        current
    end
  end
end
