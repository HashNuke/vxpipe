defmodule Vxpipe.AgentRuntime.ConservativeInputTokenCounterTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ConservativeInputTokenCounter,
    Message,
    ModelRequest,
    ModelTool,
    PendingInvocation,
    ToolCall
  }

  test "conservatively measures every model-visible input class" do
    base = ModelRequest.new([Message.system("policy")], [], [], %{}, %{request_id: "one"})
    assert {:ok, base_count} = ConservativeInputTokenCounter.count(nil, base)

    with_history = ModelRequest.with_messages(base, base.messages ++ [Message.user("hello")])
    assert {:ok, history_count} = ConservativeInputTokenCounter.count(nil, with_history)
    assert history_count > base_count

    tool = %ModelTool{
      name: "lookup",
      description: "Look up a value",
      input_schema: %{"type" => "object", "properties" => %{}}
    }

    with_tool = %{with_history | tools: [tool]}
    assert {:ok, tool_count} = ConservativeInputTokenCounter.count(nil, with_tool)
    assert tool_count > history_count

    {:ok, pending} =
      PendingInvocation.new(
        invocation_id: "call_1",
        tool_name: "lookup",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_1"
      )

    with_pending = %{with_tool | pending_invocations: [pending]}
    assert {:ok, pending_count} = ConservativeInputTokenCounter.count(nil, with_pending)
    assert pending_count > tool_count

    with_variables =
      %{with_pending | model_context: %{"call_variables" => %{"order" => %{"id" => "17"}}}}

    assert {:ok, variable_count} = ConservativeInputTokenCounter.count(nil, with_variables)
    assert variable_count > pending_count
  end

  test "counts tool relationships and UTF-8 bytes without relying on request correlation" do
    {:ok, call} = ToolCall.new(id: "call_1", name: "lookup", arguments: %{"text" => "你好"})

    messages = [
      Message.system("policy"),
      Message.assistant("calling", [call]),
      Message.tool(call, %{"status" => "completed", "value" => "世界"})
    ]

    first = ModelRequest.new(messages, [], [], %{}, %{request_id: "one"})
    second = ModelRequest.new(messages, [], [], %{}, %{request_id: "a much longer private id"})

    assert {:ok, first_count} = ConservativeInputTokenCounter.count(nil, first)
    assert {:ok, second_count} = ConservativeInputTokenCounter.count(nil, second)
    assert first_count == second_count
    assert first_count >= byte_size("policycalling你好世界")
  end
end
