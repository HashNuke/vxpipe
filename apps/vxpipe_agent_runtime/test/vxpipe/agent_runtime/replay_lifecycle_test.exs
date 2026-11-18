defmodule Vxpipe.AgentRuntime.ReplayLifecycleTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Session,
    ModelResponse,
    Message,
    ToolCall,
    ToolDescriptor,
    Conversation,
    ConversationCompaction,
    CompactionProjection
  }

  for outcome <- [:cancelled, :failed] do
    test "native exchange retains replay after #{outcome} acknowledgement" do
      outcome = unquote(outcome)
      replay = %{"format" => "test_v1", "opaque" => "private"}
      {:ok, call} = ToolCall.new(id: "native-1", name: "lookup", arguments: %{})

      {:ok, tool} =
        ToolDescriptor.new(
          name: "lookup",
          description: "Lookup",
          input_schema: %{"type" => "object", "properties" => %{}},
          binding: %{
            test_owner: self(),
            identity: :lookup,
            submission: {:accepted, :non_blocking}
          }
        )

      session =
        start_supervised!(
          {Session,
           instructions: "Be concise",
           history_mode: :host_settled,
           reply_protocol: :mode_message_v1,
           model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
           model: %{test_owner: self()},
           tools: [tool],
           executor: Vxpipe.AgentRuntime.TestExecutor,
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()}
        )

      correlation = %{request_id: "first"}
      task = Task.async(fn -> Session.request(session, "Lookup", correlation) end)
      assert_receive {:model_stream_process, provider, _}
      {:ok, response} = ModelResponse.new(text: "", tool_calls: [call], provider_replay: replay)
      send(provider, {:test_stream_response, {:ok, response}})
      assert_receive {:tool_submitted, _, :lookup, %{}, _, "native-1"}
      assert_receive {:model_stream_process, acknowledgement, request}
      assistant = Enum.find(request.messages, &(&1.role == :assistant))
      assert assistant.provider_replay == replay
      terminate_acknowledgement(session, acknowledgement, outcome)
      assert {:ok, %{status: ^outcome}} = Task.await(task)
      assert :ok = Session.discard(session, [correlation])
      assert :ok = Session.settle_output(session, correlation, nil)
      next = Task.async(fn -> Session.request(session, "Continue", %{request_id: "next"}) end)
      assert_receive {:model_stream_process, provider, recovered}
      assert assistant in recovered.messages
      assert Enum.count(recovered.messages, &(&1.tool_call_id == call.id)) == 1
      refute_received {:tool_submitted, _, _, _, _, _}
      {:ok, final} = ModelResponse.new(text: ~s({"agent_mode":"listener","message":null}))
      send(provider, {:test_stream_response, {:ok, final}})
      assert {:ok, %{status: :completed}} = Task.await(next)
    end
  end

  test "compaction retains protected replay unchanged and exposes no opaque data to summarizer" do
    {:ok, call} = ToolCall.new(id: "native-1", name: "lookup", arguments: %{})
    replay = %{"format" => "test_v1", "opaque" => "private"}
    assistant = Message.assistant("", [call], replay)

    conversation =
      Conversation.new("Policy")
      |> Conversation.append_exchange(
        [Message.user("Old"), Message.assistant("Old reply", [])],
        %{request_id: "old"},
        :durable
      )
      |> Conversation.append_exchange(
        [assistant, Message.tool(call, %{"status" => "running"})],
        %{request_id: "native"},
        :durable
      )
      |> Conversation.append_exchange([Message.user("Recent")], %{request_id: "recent"}, :durable)

    {:ok, snapshot} = ConversationCompaction.snapshot(conversation, [call.id], recent_entries: 1)

    {:ok, compacted} =
      ConversationCompaction.apply(conversation, snapshot, "Old facts", :structured)

    assert assistant in compacted.messages
    assert Enum.count(compacted.messages, &(&1.tool_call_id == call.id)) == 1

    projection =
      CompactionProjection.messages(
        [assistant, Message.tool(call, %{"status" => "running"})],
        "Summarize"
      )

    refute Enum.any?(projection, &(&1.content =~ "private"))
    assert Enum.all?(projection, &(&1.provider_replay == %{}))
  end

  defp terminate_acknowledgement(session, _provider, :cancelled),
    do: assert(:ok == Session.cancel(session))

  defp terminate_acknowledgement(_session, provider, :failed),
    do: send(provider, {:test_stream_response, {:error, :unavailable}})
end
