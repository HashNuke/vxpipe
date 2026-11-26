defmodule Vxpipe.AgentRuntime.Conversation.WorkerCommitTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Conversation, Message}
  alias Vxpipe.AgentRuntime.Conversation.WorkerCommit

  test "late delivery invalidates compaction but the worker can append subsequent tool results" do
    a = %{turn: "Florida"}
    b = %{turn: "completion"}
    base = Conversation.new("Policy") |> append("old", a) |> append("result", b)
    heard = Message.assistant("Let me save that.", [])
    authoritative = Conversation.settle_delivery(base, heard, a)
    compacted = Conversation.new("Policy") |> append("summary", b)
    # A compaction commits on its own before a provider response is processed.
    assert WorkerCommit.merge(authoritative, base.entries, compacted) == authoritative
    after_tool = append(compacted, "correction tool", b)
    merged = WorkerCommit.merge(authoritative, compacted.entries, after_tool)

    assert Enum.map(merged.messages, & &1.content) ==
             ["Policy", "old", "Let me save that.", "result", "correction tool"]

    assert WorkerCommit.merge(merged, after_tool.entries, after_tool) == merged
  end

  test "separate equal exchanges are retained, including after a current-base compaction" do
    a = %{turn: "x"}
    base = Conversation.new("Policy") |> append("old", a)
    compacted = Conversation.new("Policy") |> append("summary", a)
    accepted = WorkerCommit.merge(base, base.entries, compacted)
    assert accepted.entries == compacted.entries
    after_tool = append(compacted, "summary", a)
    merged = WorkerCommit.merge(accepted, compacted.entries, after_tool)
    assert Enum.map(merged.messages, & &1.content) == ["Policy", "summary", "summary"]
  end

  defp append(conversation, text, correlation),
    do: Conversation.append_exchange(conversation, [Message.user(text)], correlation, :durable)
end
