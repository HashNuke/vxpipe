defmodule Vxpipe.AgentRuntime.ContextPreparationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    CompactionObservation,
    CompactionResult,
    ContextBudget,
    ContextPreparation,
    Conversation,
    Message,
    ModelRequest,
    ModelTool,
    PendingInvocation,
    ToolCall
  }

  test "compacts selected history once and remeasures the complete prepared request" do
    {conversation, pending} = conversation_with_pending_tool()
    current = append_exchange(conversation, "current", :discardable)
    staged = Message.user("new caller work")
    request = model_request(current.messages ++ [staged], pending)
    budget = budget()
    config = config(budget)

    preparation =
      Task.async(fn -> ContextPreparation.prepare(current, request, config) end)

    assert_count_request(request, 600)

    assert_receive {:input_tokens_counted, counter, protected_request}
    assert protected_request.tools == request.tools
    assert protected_request.pending_invocations == request.pending_invocations
    assert protected_request.model_context == request.model_context
    refute Enum.any?(protected_request.messages, &(&1.content == "old user"))
    assert List.last(protected_request.messages) == staged
    send(counter, {:input_token_count, 300})

    assert_receive {:context_compaction_requested, compactor, compaction_request}
    assert Enum.map(compaction_request.messages, & &1.content) == ["old user", "old assistant"]
    assert compaction_request.maximum_summary_tokens == 99
    assert compaction_request.correlation == request.correlation
    assert compaction_request.source_correlations == [%{request_id: "old"}]

    {:ok, compaction_result} =
      CompactionResult.new(
        summary: "The caller previously discussed an old request.",
        usage: %{input_tokens: 40, output_tokens: 12},
        provider_metadata: %{model: "test:summarizer"}
      )

    send(compactor, {:context_compaction_result, {:ok, compaction_result}})

    assert_receive {:input_tokens_counted, counter, compacted_request}
    assert compacted_request.tools == request.tools
    assert compacted_request.pending_invocations == request.pending_invocations
    assert compacted_request.model_context == request.model_context
    assert List.last(compacted_request.messages) == staged
    assert Enum.any?(compacted_request.messages, &(&1.origin == :derived_summary))
    send(counter, {:input_token_count, 350})

    assert {:ok, prepared} = Task.await(preparation)
    assert prepared.input_tokens == 350
    assert prepared.compaction.usage == %{input_tokens: 40, output_tokens: 12}
    assert prepared.compaction.provider_metadata == %{model: "test:summarizer"}
    assert prepared.request == compacted_request
    assert prepared.conversation.messages ++ [staged] == compacted_request.messages

    refute Enum.any?(current.messages, &(&1.origin == :derived_summary))
    assert Enum.any?(current.messages, &(&1.content == "old user"))
  end

  test "does not invoke a compactor below the trigger" do
    conversation = base_conversation() |> append_exchange("recent", :discardable)
    request = model_request(conversation.messages ++ [Message.user("current")], [])
    configuration = config(budget())

    task = Task.async(fn -> ContextPreparation.prepare(conversation, request, configuration) end)

    assert_count_request(request, 599)

    assert {:ok, prepared} = Task.await(task)
    assert prepared.conversation == conversation
    assert prepared.request == request
    assert prepared.compaction == nil
    refute_receive {:context_compaction_requested, _compactor, _request}
  end

  test "fails before compaction when protected input fills the usable window" do
    conversation =
      base_conversation()
      |> append_exchange("old", :discardable)
      |> append_exchange("recent", :discardable)

    request = model_request(conversation.messages ++ [Message.user("current")], [])
    configuration = config(budget())
    task = Task.async(fn -> ContextPreparation.prepare(conversation, request, configuration) end)

    assert_count_request(request, 700)
    assert_receive {:input_tokens_counted, counter, _protected_request}
    send(counter, {:input_token_count, 800})

    assert {:error, :protected_context_too_large} = Task.await(task)
    refute_receive {:context_compaction_requested, _compactor, _request}
    refute Enum.any?(conversation.messages, &(&1.origin == :derived_summary))
  end

  test "leaves original context intact after compactor failure" do
    conversation =
      base_conversation()
      |> append_exchange("old", :discardable)
      |> append_exchange("recent", :discardable)

    request = model_request(conversation.messages ++ [Message.user("current")], [])
    configuration = config(budget())
    task = Task.async(fn -> ContextPreparation.prepare(conversation, request, configuration) end)

    assert_count_request(request, 700)
    assert_receive {:input_tokens_counted, counter, _protected_request}
    send(counter, {:input_token_count, 300})
    assert_receive {:context_compaction_requested, compactor, _compaction_request}
    send(compactor, {:context_compaction_result, {:error, :provider_timeout}})

    assert {:error, :context_compaction_unavailable,
            %CompactionObservation{
              outcome: :failed,
              usage: %{},
              provider_metadata: %{}
            }} = Task.await(task)

    assert Enum.any?(conversation.messages, &(&1.content == "old user"))
    refute Enum.any?(conversation.messages, &(&1.origin == :derived_summary))
  end

  test "rejects a summary that misses an achievable below-half target" do
    conversation =
      base_conversation()
      |> append_exchange("old", :discardable)
      |> append_exchange("recent", :discardable)

    request = model_request(conversation.messages ++ [Message.user("current")], [])
    configuration = config(budget())
    task = Task.async(fn -> ContextPreparation.prepare(conversation, request, configuration) end)

    assert_count_request(request, 700)
    assert_receive {:input_tokens_counted, counter, _protected_request}
    send(counter, {:input_token_count, 300})
    assert_receive {:context_compaction_requested, compactor, _compaction_request}

    {:ok, result} =
      CompactionResult.new(
        summary: "A summary that is still too large",
        usage: %{total_tokens: 21},
        provider_metadata: %{request_id: "compaction-too-large"}
      )

    send(compactor, {:context_compaction_result, {:ok, result}})

    assert_receive {:input_tokens_counted, counter, _compacted_request}
    send(counter, {:input_token_count, 450})

    assert {:error, :compacted_context_too_large,
            %CompactionObservation{
              outcome: :failed,
              usage: %{total_tokens: 21},
              provider_metadata: %{request_id: "compaction-too-large"}
            }} = Task.await(task)

    refute Enum.any?(conversation.messages, &(&1.origin == :derived_summary))
  end

  defp config(budget) do
    %{
      budget: budget,
      compactor: {Vxpipe.AgentRuntime.TestContextCompactor, %{owner: self(), result: :manual}},
      compactor_timeout_ms: 1_000,
      input_token_counter:
        {Vxpipe.AgentRuntime.TestInputTokenCounter, %{owner: self(), result: :manual}},
      input_token_timeout_ms: 1_000,
      recent_entries: 1
    }
  end

  defp budget do
    {:ok, budget} =
      ContextBudget.new(context_window_tokens: 1_000, output_reserve_tokens: 200)

    budget
  end

  defp assert_count_request(expected_request, count) do
    assert_receive {:input_tokens_counted, counter, ^expected_request}
    send(counter, {:input_token_count, count})
  end

  defp base_conversation do
    Conversation.new("System instructions", [Message.user("Transferred history")])
  end

  defp append_exchange(conversation, label, retention) do
    Conversation.append_exchange(
      conversation,
      [Message.user(label <> " user"), Message.assistant(label <> " assistant", [])],
      %{request_id: label},
      retention
    )
  end

  defp conversation_with_pending_tool do
    conversation = base_conversation() |> append_exchange("old", :durable)

    {:ok, call} =
      ToolCall.new(id: "tool_running", name: "fetch_order", arguments: %{"id" => "17"})

    conversation =
      Conversation.append_exchange(
        conversation,
        [
          Message.user("pending user"),
          Message.assistant("pending assistant", [call]),
          Message.tool(call, %{"invocation_id" => call.id, "status" => "running"})
        ],
        %{request_id: "pending"},
        :durable
      )

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: call.id,
        tool_name: call.name,
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_pending"
      )

    {conversation, pending}
  end

  defp model_request(messages, pending) do
    tool = %ModelTool{
      name: "fetch_order",
      description: "Fetch an order",
      input_schema: %{
        "type" => "object",
        "properties" => %{"id" => %{"type" => "string"}}
      }
    }

    ModelRequest.new(
      messages,
      [tool],
      List.wrap(pending),
      %{"call_variables" => %{"order" => %{"value" => %{"id" => "17"}}}},
      %{activation_id: "activation_1", request_id: "current"}
    )
  end
end
