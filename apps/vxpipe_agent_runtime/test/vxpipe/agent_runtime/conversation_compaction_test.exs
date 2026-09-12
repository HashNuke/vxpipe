defmodule Vxpipe.AgentRuntime.ConversationCompactionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    Conversation,
    ConversationCompaction,
    ConversationCompactionSnapshot,
    Message,
    ToolCall
  }

  test "selects only an old contiguous prefix and protects pending tool relationships" do
    conversation = base_conversation()
    old = exchange(conversation, "old", :discardable)
    pending = tool_exchange(old, "pending_call")
    after_pending = exchange(pending, "after pending", :discardable)
    current = exchange(after_pending, "current", :discardable)

    assert {:ok, snapshot} =
             ConversationCompaction.snapshot(current, ["pending_call"], recent_entries: 1)

    assert contents(snapshot.selected_entries) == ["old user", "old assistant"]

    assert contents(ConversationCompactionSnapshot.retained_entries(snapshot)) == [
             "System policy",
             "Transferred history",
             "pending user",
             "pending assistant",
             ~s({"invocation_id":"pending_call","status":"running"}),
             "after pending user",
             "after pending assistant",
             "current user",
             "current assistant"
           ]
  end

  test "protects permanent transfer history and the configured recent tail" do
    conversation =
      base_conversation()
      |> exchange("first", :discardable)
      |> exchange("second", :durable)
      |> exchange("third", :discardable)
      |> exchange("fourth", :discardable)

    assert {:ok, snapshot} =
             ConversationCompaction.snapshot(conversation, [], recent_entries: 2)

    assert contents(snapshot.selected_entries) == [
             "first user",
             "first assistant",
             "second user",
             "second assistant"
           ]

    assert contents(ConversationCompactionSnapshot.retained_entries(snapshot)) == [
             "System policy",
             "Transferred history",
             "third user",
             "third assistant",
             "fourth user",
             "fourth assistant"
           ]
  end

  test "merges entries appended after the snapshot and retains durable correlation evidence" do
    conversation =
      base_conversation()
      |> exchange("first", :durable)
      |> exchange("recent", :discardable)

    assert {:ok, snapshot} =
             ConversationCompaction.snapshot(conversation, [], recent_entries: 1)

    late = exchange(conversation, "late completion", :durable)

    assert {:ok, compacted} =
             ConversationCompaction.apply(late, snapshot, "The caller discussed the first item.")

    assert Enum.map(compacted.messages, &{&1.role, &1.origin}) == [
             {:system, nil},
             {:user, :caller},
             {:assistant, :derived_summary},
             {:user, :caller},
             {:assistant, nil},
             {:user, :caller},
             {:assistant, nil}
           ]

    summary = Enum.at(compacted.messages, 2)
    assert summary.tool_calls == []
    assert summary.tool_call_id == nil
    assert summary.content =~ "untrusted historical data"
    assert summary.content =~ "The caller discussed the first item."

    assert Conversation.durable?(compacted, %{request_id: "first"})
    assert Conversation.durable?(compacted, %{request_id: "late completion"})
  end

  test "rejects a stale snapshot without changing current history" do
    conversation =
      base_conversation()
      |> exchange("first", :discardable)
      |> exchange("recent", :discardable)

    assert {:ok, snapshot} =
             ConversationCompaction.snapshot(conversation, [], recent_entries: 1)

    changed = Conversation.discard(conversation, [%{request_id: "first"}])

    assert {:error, :stale_compaction_snapshot} =
             ConversationCompaction.apply(changed, snapshot, "Must not attach")

    refute Enum.any?(changed.messages, &(&1.origin == :derived_summary))
  end

  test "reports when protected history leaves no compaction candidate" do
    conversation = base_conversation() |> exchange("only recent", :discardable)

    assert {:error, :no_compactable_history} =
             ConversationCompaction.snapshot(conversation, [], recent_entries: 1)
  end

  defp base_conversation do
    Conversation.new("System policy", [Message.user("Transferred history")])
  end

  defp exchange(conversation, label, retention) do
    Conversation.append_exchange(
      conversation,
      [Message.user(label <> " user"), Message.assistant(label <> " assistant", [])],
      %{request_id: label},
      retention
    )
  end

  defp tool_exchange(conversation, invocation_id) do
    {:ok, call} =
      ToolCall.new(id: invocation_id, name: "fetch_order", arguments: %{"id" => "17"})

    Conversation.append_exchange(
      conversation,
      [
        Message.user("pending user"),
        Message.assistant("pending assistant", [call]),
        Message.tool(call, %{"invocation_id" => invocation_id, "status" => "running"})
      ],
      %{request_id: "pending"},
      :durable
    )
  end

  defp contents(entries) do
    Enum.flat_map(entries, fn entry -> Enum.map(entry.messages, & &1.content) end)
  end
end
