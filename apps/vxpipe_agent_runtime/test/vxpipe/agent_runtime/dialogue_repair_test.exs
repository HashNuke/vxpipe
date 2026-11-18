defmodule Vxpipe.AgentRuntime.DialogueRepairTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Event, Message, ModelResponse, Session, ToolCall, ToolDescriptor}

  test "one correction shares output allowance, meters both attempts and excludes private context" do
    session = session()
    correlation = %{request_id: "repair"}
    task = Task.async(fn -> Session.request(session, "Hello", correlation) end)
    assert_receive {:model_stream_process, provider, first}
    assert first.maximum_output_tokens == 100
    reply(provider, "malformed-private", %{input_tokens: 8, output_tokens: 30})
    assert_receive {:model_stream_process, ^provider, repair}
    assert repair.maximum_output_tokens == 70
    assert Enum.take(repair.messages, length(first.messages)) == first.messages
    assert Enum.any?(repair.messages, &(&1.content == "malformed-private"))
    assert repair.tools == first.tools

    reply(provider, ~s({"agent_mode":"speaker","message":"Hello."}), %{
      input_tokens: 15,
      output_tokens: 20
    })

    assert {:ok, %{status: :completed, dialogue: %{message: "Hello."}, output: nil}} =
             Task.await(task)

    for usage <- [%{input_tokens: 8, output_tokens: 30}, %{input_tokens: 15, output_tokens: 20}] do
      usage = Map.put(usage, :usage_reported, %{output: true})
      assert_receive {:agent_runtime_event, %Event{kind: :model_usage, data: %{usage: ^usage}}}
      assert_receive {:agent_runtime_event, %Event{kind: :model_attempt_started}}
    end

    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
    {:ok, spoken} = Message.spoken_assistant("agent", "Hello.", :speaker)
    assert :ok = Session.settle_output(session, correlation, spoken)
    next = Task.async(fn -> Session.request(session, "Next", %{request_id: "next"}) end)
    assert_receive {:model_stream_process, next_provider, next_request}
    assert next_request.messages == first.messages ++ [spoken, Message.user("Next")]
    reply(next_provider, ~s({"agent_mode":"listener","message":null}))
    assert {:ok, %{status: :completed}} = Task.await(next)
  end

  test "repair cannot dispatch tools or request another correction" do
    for result <- [:tool, :malformed] do
      session = session(id: result)
      task = Task.async(fn -> Session.request(session, "Hello", %{}) end)
      assert_receive {:model_stream_process, provider, first}
      reply(provider, "bad")
      assert_receive {:model_stream_process, ^provider, repair}
      assert repair.tools == first.tools
      assert [%{name: "lookup"}] = repair.tools

      case result do
        :tool -> reply(provider, "", %{output_tokens: 10}, [call("repair-tool")])
        :malformed -> reply(provider, "still bad")
      end

      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} = Task.await(task)
      refute_received {:model_stream_process, _, _}
      refute_received {:tool_submitted, _, _, _, _, _}
      refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
    end
  end

  test "cancellation fences correction and no repair content enters the next request" do
    session = session()
    correlation = %{request_id: "cancel"}
    task = Task.async(fn -> Session.request(session, "Hello", correlation) end)
    assert_receive {:model_stream_process, provider, first}
    reply(provider, "private-bad")
    assert_receive {:model_stream_process, ^provider, _repair}
    monitor = Process.monitor(provider)
    assert :ok = Session.cancel(session)
    assert {:ok, %{status: :cancelled}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}
    assert :ok = Session.settle_output(session, correlation, nil)
    next = Task.async(fn -> Session.request(session, "Next", %{}) end)
    assert_receive {:model_stream_process, next_provider, request}
    assert request.messages == first.messages ++ [Message.user("Next")]
    reply(next_provider, ~s({"agent_mode":"listener","message":null}))
    assert {:ok, %{status: :completed}} = Task.await(next)
  end

  test "the original request deadline terminates a blocked correction" do
    session = session(request_timeout_ms: 1_000)
    task = Task.async(fn -> Session.request(session, "Hello", %{}) end)
    assert_receive {:model_stream_process, provider, _}
    reply(provider, "bad")
    assert_receive {:model_stream_process, ^provider, _}
    monitor = Process.monitor(provider)
    assert {:ok, %{status: :failed, reason: :request_timeout}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}
    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
  end

  test "missing, invalid, conflicting or exhausted budgets do not authorize correction" do
    cases = [
      {%{}, [], %{output_limit: nil}},
      {%{output_tokens: 10}, [], %{context_window: nil}},
      {%{}, [], %{}},
      {%{output_tokens: -1}, [], %{}},
      {%{output_tokens: 0, usage_reported: %{output: false}}, [], %{}},
      {%{output_tokens: 0, usage_reported: nil}, [], %{}},
      {%{output_tokens: 10, billing_usage_complete: false}, [], %{}},
      {%{output_tokens: 1.5}, [], %{}},
      {%{output_tokens: 100}, [], %{}},
      {%{output_tokens: 101}, [], %{}},
      {%{"output_tokens" => 10, :output_tokens => 20}, [], %{}},
      {%{output_tokens: 10}, [maximum_model_rounds: 1], %{}},
      {%{output_tokens: 10}, [], %{context_window: 100}}
    ]

    for {{usage, options, model}, index} <- Enum.with_index(cases) do
      session = session([id: index, model_overrides: model] ++ options)
      task = Task.async(fn -> Session.request(session, "Hello", %{}) end)
      assert_receive {:model_stream_process, provider, _}
      reply(provider, "bad", usage)
      assert {:ok, %{status: :failed, reason: :invalid_dialogue}} = Task.await(task)
      refute_received {:model_stream_process, _, _}
    end
  end

  test "modern blocking acknowledgments retain tools but malformed output after dispatch cannot retry" do
    session = session()
    task = Task.async(fn -> Session.request(session, "Lookup", %{}) end)
    assert_receive {:model_stream_process, provider, first}
    reply(provider, "", %{output_tokens: 10}, [call("original")])
    assert_receive {:tool_submitted, _, :lookup, %{}, %{}, "original"}
    assert_receive {:model_stream_process, ^provider, next}
    assert next.tools == first.tools
    assert List.last(next.messages).role == :tool
    reply(provider, "bad")
    assert {:ok, %{status: :failed, reason: :invalid_dialogue}} = Task.await(task)
    refute_received {:model_stream_process, _, _}
    refute_received {:tool_submitted, _, _, _, _, _}
  end

  test "partial failure and oversized output never invoke correction" do
    for {result, reason} <- [{:transport, :provider_unavailable}, {:oversized, :output_too_large}] do
      session = session(id: result, maximum_output_bytes: 30)
      task = Task.async(fn -> Session.request(session, "Hello", %{}) end)
      assert_receive {:model_stream_process, provider, _}

      case result do
        :transport ->
          send(provider, {:test_stream_delta, "partial"})
          send(provider, {:test_stream_response, {:error, :upstream_failed}})

        :oversized ->
          reply(provider, String.duplicate("x", 31))
      end

      assert {:ok, %{status: :failed, reason: ^reason}} = Task.await(task)
      refute_received {:model_stream_process, _, _}
      refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
    end
  end

  test "restart retains the captured policy and unknown private policy versions fail" do
    limits = start_supervised!({Agent, fn -> %{output_limit: 100, context_window: 20_000} end})
    {_id, options} = session_options(model_overrides: %{limits_source: limits})
    child = Session.child_spec(options)
    {Session, :start_link, [pinned]} = child.start
    policy = Keyword.fetch!(pinned, :reply_repair_policy)
    assert policy.version == :bounded_once_v1

    assert {:error, :invalid_configuration} =
             Vxpipe.AgentRuntime.SessionConfiguration.new(
               Keyword.put(pinned, :reply_repair_policy, %{policy | version: :unknown})
             )

    supervisor =
      start_supervised!(%{
        id: :repair_restart_supervisor,
        start:
          {Supervisor, :start_link,
           [[child], [strategy: :one_for_one, name: __MODULE__.RestartSupervisor]]}
      })

    [{_, original, _, _}] = Supervisor.which_children(supervisor)
    Agent.update(limits, &%{&1 | output_limit: 200})
    monitor = Process.monitor(original)
    assert :ok = Supervisor.terminate_child(supervisor, Session)
    assert_receive {:DOWN, ^monitor, :process, ^original, _}
    assert {:ok, restarted} = Supervisor.restart_child(supervisor, Session)
    task = Task.async(fn -> Session.request(restarted, "Hello", %{}) end)
    assert_receive {:model_stream_process, provider, request}
    assert request.maximum_output_tokens == 100
    reply(provider, ~s({"agent_mode":"listener","message":null}))
    assert {:ok, %{status: :completed}} = Task.await(task)
    refute_received {:model_stream_process, _, _}
  end

  test "the tighter compaction output reserve applies to both attempts" do
    session =
      session(
        context_compaction: [
          enabled: true,
          context_window_tokens: 20_000,
          output_reserve_tokens: 60,
          compactor: {Vxpipe.AgentRuntime.TestContextCompactor, %{owner: self(), result: :manual}}
        ]
      )

    task = Task.async(fn -> Session.request(session, "Hello", %{}) end)
    assert_receive {:model_stream_process, provider, first}
    assert first.maximum_output_tokens == 60
    reply(provider, "bad")
    assert_receive {:model_stream_process, ^provider, second}
    assert second.maximum_output_tokens == 50
    reply(provider, ~s({"agent_mode":"listener","message":null}))
    assert {:ok, %{status: :completed}} = Task.await(task)
    refute_received {:context_compaction_requested, _, _}
  end

  defp session(options \\ []) do
    {id, options} = session_options(options)
    start_supervised!({Session, options}, id: id)
  end

  defp session_options(options) do
    {id, options} = Keyword.pop(options, :id, make_ref())
    {model, options} = Keyword.pop(options, :model_overrides, %{})

    {:ok, tool} =
      ToolDescriptor.new(
        name: "lookup",
        description: "Lookup",
        input_schema: %{"type" => "object"},
        binding: %{test_owner: self(), identity: :lookup, submission: {:accepted, :blocking}}
      )

    defaults = [
      instructions: "Be concise",
      history_mode: :host_settled,
      reply_protocol: :mode_message_v1,
      model_provider: Vxpipe.AgentRuntime.RepairModelProvider,
      model: Map.merge(%{test_owner: self(), output_limit: 100, context_window: 20_000}, model),
      tools: [tool],
      executor: Vxpipe.AgentRuntime.TestExecutor,
      pending_context_source:
        {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
      event_destination: self()
    ]

    {id, Keyword.merge(defaults, options)}
  end

  defp call(id) do
    {:ok, call} = ToolCall.new(id: id, name: "lookup", arguments: %{})
    call
  end

  defp reply(provider, text, usage \\ %{output_tokens: 10}, calls \\ []) do
    {:ok, response} =
      ModelResponse.new(
        text: text,
        usage: Map.put_new(usage, :usage_reported, %{output: true}),
        tool_calls: calls
      )

    send(provider, {:test_stream_response, {:ok, response}})
  end
end
