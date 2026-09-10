defmodule Vxpipe.AgentRuntime.RequestDeadlineTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelResponse, Result, Session, ToolCall, ToolDescriptor}

  test "terminates provider work when the request deadline expires" do
    session = start_session([], request_timeout_ms: 500)
    caller = request(session, "Do not retain me", "req_timeout_1")
    release_pending_context("req_timeout_1")

    assert_receive {:model_provider_process, provider, _request}
    provider_monitor = Process.monitor(provider)

    assert {:ok, %Result{status: :failed, reason: :request_timeout}} =
             Task.await(caller, 1_000)

    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}
    assert Session.status(session) == :idle

    next_caller = request(session, "Retain me", "req_timeout_2")
    release_pending_context("req_timeout_2")
    assert_receive {:model_provider_process, next_provider, next_request}
    assert Enum.map(next_request.messages, & &1.role) == [:system, :user]
    assert List.last(next_request.messages).content == "Retain me"

    reply_with_text(next_provider, "Retained.")
    assert {:ok, %Result{status: :completed}} = Task.await(next_caller)
  end

  test "defers an expired deadline until a submitted tool exchange commits" do
    descriptor = tool_descriptor({:await_release, {:accepted, :non_blocking}})
    session = start_session([descriptor], request_timeout_ms: 500)
    caller = request(session, "Check my balance", "req_timeout_tool_1")
    release_pending_context("req_timeout_tool_1")

    assert_receive {:model_provider_process, provider, _request}
    reply_with_tool(provider)
    assert_receive {:tool_submitted, executor, :balance, _arguments, _context, "tool_call_1"}

    assert Task.yield(caller, 750) == nil
    send(executor, :release_submission)

    assert {:ok, %Result{status: :failed, reason: :request_timeout}} = Task.await(caller)

    next_caller = request(session, "What are the card rules?", "req_timeout_tool_2")
    release_pending_context("req_timeout_tool_2")
    assert_receive {:model_provider_process, next_provider, next_request}

    assert Enum.map(next_request.messages, & &1.role) == [
             :system,
             :user,
             :assistant,
             :tool,
             :user
           ]

    reply_with_text(next_provider, "The rules are available.")
    assert {:ok, %Result{status: :completed}} = Task.await(next_caller)
  end

  defp start_session(tools, options) do
    defaults = [
      instructions: "Be concise",
      model_provider: Vxpipe.AgentRuntime.TestModelProvider,
      model: %{mode: :scripted, test_owner: self()},
      tools: tools,
      executor: if(tools == [], do: nil, else: Vxpipe.AgentRuntime.TestExecutor),
      maximum_model_rounds: 2,
      pending_context_source:
        {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
      event_destination: self()
    ]

    start_supervised!({Session, Keyword.merge(defaults, options)})
  end

  defp request(session, input, request_id) do
    Task.async(fn -> Session.request(session, input, %{request_id: request_id}) end)
  end

  defp release_pending_context(request_id) do
    assert_receive {:pending_context_requested, source, %{request_id: ^request_id}, 1_000}
    send(source, {:release, {:ok, []}})
  end

  defp reply_with_tool(provider) do
    {:ok, call} =
      ToolCall.new(
        id: "tool_call_1",
        name: "check_balance",
        arguments: %{"account_id" => "account_1"}
      )

    {:ok, response} = ModelResponse.new(text: "I will check.", tool_calls: [call])
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp reply_with_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp tool_descriptor(submission) do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: "check_balance",
        description: "Check an account balance",
        input_schema: %{
          "type" => "object",
          "properties" => %{"account_id" => %{"type" => "string"}},
          "required" => ["account_id"],
          "additionalProperties" => false
        },
        binding: %{test_owner: self(), identity: :balance, submission: submission}
      )

    descriptor
  end
end
