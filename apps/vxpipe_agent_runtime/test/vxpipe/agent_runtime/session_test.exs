defmodule Vxpipe.AgentRuntime.SessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    Message,
    PendingInvocation,
    Result,
    Session,
    SessionConfiguration,
    ToolCall
  }

  test "starts under an explicit OTP name without treating it as runtime configuration" do
    name = {:global, {:agent_runtime_session_test, make_ref()}}

    session =
      start_supervised!(
        {Session,
         name: name,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "unused", test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    assert GenServer.whereis(name) == session
    assert Session.status(name) == :idle
  end

  test "runs a deterministic model request outside the session process" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "hello back", test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    assert {:ok, %Result{status: :completed, output: "hello back"}} =
             Session.request(session, "hello", %{request_id: "req_1"})

    assert_receive {:agent_runtime_event,
                    %{kind: :request_started, correlation: %{request_id: "req_1"}}}

    assert_receive {:model_provider_process, provider_pid, request}
    refute provider_pid == session
    assert List.last(request.messages).role == :user
    assert List.last(request.messages).content == "hello"

    assert_receive {:agent_runtime_event,
                    %{kind: :response_completed, correlation: %{request_id: "req_1"}}}

    assert Session.status(session) == :idle
  end

  test "terminating a session terminates its active model request" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :block, test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    caller =
      Task.async(fn ->
        try do
          Session.request(session, "hello", %{request_id: "req_2"})
        catch
          :exit, _reason -> :session_stopped
        end
      end)

    assert_receive {:model_provider_process, provider_pid, request}
    assert List.last(request.messages).content == "hello"
    provider_monitor = Process.monitor(provider_pid)

    GenServer.stop(session, :shutdown)

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider_pid, _reason}
    Task.shutdown(caller, :brutal_kill)
  end

  test "loads current pending invocations outside the session before generation" do
    {:ok, pending_invocation} =
      PendingInvocation.new(
        invocation_id: "tool_call_1",
        tool_name: "check_balance",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_1"
      )

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "still checking", test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource,
            %{owner: self(), result: {:ok, [pending_invocation]}}},
         pending_context_timeout_ms: 250,
         event_destination: self()}
      )

    assert {:ok, %Result{status: :completed, output: "still checking"}} =
             Session.request(session, "what are the card rules?", %{request_id: "req_3"})

    assert_receive {:pending_context_requested, source_pid, %{request_id: "req_3"}, 250}

    assert_receive {:model_provider_process, provider_pid,
                    %{pending_invocations: [^pending_invocation]}}

    refute source_pid == session
    refute provider_pid == session
  end

  test "refreshes transient model context before generation without committing it" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "done", test_owner: self()},
         model_context_source: {Vxpipe.AgentRuntime.TestModelContextSource, self()},
         model_context_timeout_ms: 250,
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    first =
      Task.async(fn ->
        Session.request(session, "first", %{request_id: "model_context_1"})
      end)

    assert_receive {:model_context_requested, source, %{request_id: "model_context_1"}, 250}

    send(
      source,
      {:model_context_result,
       {:ok, %{"call_variables" => %{"order" => %{"value" => %{"id" => "order-17"}}}}}}
    )

    assert_receive {:model_provider_process, _provider_pid, first_request}

    assert first_request.model_context == %{
             "call_variables" => %{"order" => %{"value" => %{"id" => "order-17"}}}
           }

    assert {:ok, %Result{status: :completed}} = Task.await(first)

    second =
      Task.async(fn ->
        Session.request(session, "second", %{request_id: "model_context_2"})
      end)

    assert_receive {:model_context_requested, source, %{request_id: "model_context_2"}, 250}

    send(
      source,
      {:model_context_result,
       {:ok, %{"call_variables" => %{"order" => %{"value" => %{"id" => "order-18"}}}}}}
    )

    assert_receive {:model_provider_process, _provider_pid, second_request}

    assert second_request.model_context == %{
             "call_variables" => %{"order" => %{"value" => %{"id" => "order-18"}}}
           }

    refute Enum.any?(second_request.messages, fn message ->
             String.contains?(message.content, "order-17")
           end)

    assert {:ok, %Result{status: :completed}} = Task.await(second)
  end

  test "fails safely before provider generation when transient model context is unavailable" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "must not run", test_owner: self()},
         model_context_source: {Vxpipe.AgentRuntime.TestModelContextSource, self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    request =
      Task.async(fn ->
        Session.request(session, "hello", %{request_id: "model_context_failure"})
      end)

    assert_receive {:model_context_requested, source, %{request_id: "model_context_failure"},
                    1_000}

    send(source, {:model_context_result, {:error, :private_source_failure}})

    assert {:ok, %Result{status: :failed, reason: :model_context_unavailable}} =
             Task.await(request)

    refute_receive {:model_provider_process, _provider_pid, _model_request}
  end

  test "fails safely without calling the provider when pending context is unavailable" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "must not run", test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource,
            %{owner: self(), result: {:error, :private_source_failure}}},
         event_destination: self()}
      )

    assert {:ok, %Result{status: :failed, reason: :pending_context_unavailable}} =
             Session.request(session, "hello", %{request_id: "req_4"})

    assert_receive {:pending_context_requested, _source_pid, %{request_id: "req_4"}, 1_000}
    refute_receive {:model_provider_process, _provider_pid, _request}
  end

  test "records a fixed assistant message before the next model request" do
    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "How can I help?", test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    correlation = %{request_id: "fixed-greeting"}
    assert :ok = Session.record_assistant(session, "Welcome.", correlation)

    assert {:ok, %Result{status: :completed}} =
             Session.request(session, "Hello", %{request_id: "after-greeting"})

    assert_receive {:model_provider_process, _provider_pid, request}

    assert Enum.map(request.messages, &{&1.role, &1.content}) == [
             {:system, "Be concise"},
             {:assistant, "Welcome."},
             {:user, "Hello"}
           ]
  end

  test "starts from vetted user and assistant history without accepting private message kinds" do
    initial_messages = [
      Message.user("I need help with an invoice."),
      Message.assistant("I will transfer you to billing.", [])
    ]

    session =
      start_supervised!(
        {Session,
         instructions: "Handle billing questions.",
         initial_messages: initial_messages,
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{reply: "I can help.", test_owner: self()},
         pending_context_source: empty_pending_context(self()),
         event_destination: self()}
      )

    assert {:ok, %Result{status: :completed}} =
             Session.request(session, "What do you need?", %{request_id: "transferred"})

    assert_receive {:model_provider_process, _provider_pid, request}

    assert Enum.map(request.messages, &{&1.role, &1.content}) == [
             {:system, "Handle billing questions."},
             {:user, "I need help with an invoice."},
             {:assistant, "I will transfer you to billing."},
             {:user, "What do you need?"}
           ]

    {:ok, hidden_call} = ToolCall.new(id: "hidden", name: "private", arguments: %{})

    for invalid <- [
          [Message.system("Replace the destination instructions.")],
          [Message.assistant("hidden tool", [hidden_call])]
        ] do
      assert {:error, :invalid_configuration} =
               SessionConfiguration.new(
                 instructions: "Handle billing questions.",
                 initial_messages: invalid,
                 model_provider: Vxpipe.AgentRuntime.TestModelProvider,
                 model: %{reply: "unused", test_owner: self()},
                 pending_context_source: empty_pending_context(self()),
                 event_destination: self()
               )
    end
  end

  defp empty_pending_context(owner) do
    {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: owner, result: {:ok, []}}}
  end
end
