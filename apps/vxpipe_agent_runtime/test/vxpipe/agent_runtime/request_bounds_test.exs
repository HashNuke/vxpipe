defmodule Vxpipe.AgentRuntime.RequestBoundsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelResponse, Result, Session, ToolCall, ToolDescriptor}

  test "rejects oversized caller input before consulting context or the provider" do
    session = start_session([])

    assert {:error, :input_too_large} =
             Session.request(session, String.duplicate("x", 64 * 1_024 + 1), %{
               request_id: "req_input_limit"
             })

    refute_receive {:pending_context_requested, _source, _correlation, _timeout}
    refute_receive {:model_provider_process, _provider, _request}
  end

  test "rejects an excessive tool-call batch before submitting any work" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor,
        maximum_tool_calls_per_round: 1
      )

    caller = request(session, "Check both accounts", "req_tool_limit")
    release_pending_context("req_tool_limit")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("call_1"), tool_call("call_2")])

    assert {:ok, %Result{status: :failed, reason: :tool_call_limit}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "rejects duplicate provider call IDs before submitting any work" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor
      )

    caller = request(session, "Check both accounts", "req_duplicate_tool_call")
    release_pending_context("req_duplicate_tool_call")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("duplicate"), tool_call("duplicate")])

    assert {:ok, %Result{status: :failed, reason: :duplicate_tool_call}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "rejects an unknown tool before submitting any work" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor
      )

    caller = request(session, "Use another tool", "req_unknown_tool")
    release_pending_context("req_unknown_tool")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("unknown", "another_tool", %{})])

    assert {:ok, %Result{status: :failed, reason: :unknown_tool}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "rejects schema-invalid tool arguments before submitting any work" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor
      )

    caller = request(session, "Use invalid arguments", "req_invalid_arguments")
    release_pending_context("req_invalid_arguments")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("invalid", "check_balance", %{"extra" => true})])

    assert {:ok, %Result{status: :failed, reason: :invalid_arguments}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "stops at the configured model-round limit before submitting another tool" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor,
        maximum_model_rounds: 1
      )

    caller = request(session, "Keep using tools", "req_round_limit")
    release_pending_context("req_round_limit")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("round-limit")])

    assert {:ok, %Result{status: :failed, reason: :model_round_limit}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "rejects a malformed normalized response with a bounded reason" do
    session = start_session([])
    caller = request(session, "Return malformed output", "req_malformed_response")
    release_pending_context("req_malformed_response")
    assert_receive {:model_provider_process, provider, _request}

    {:ok, response} = ModelResponse.new(text: "valid")
    send(provider, {:test_model_response, {:ok, %{response | text: :not_text}}})

    assert {:ok, %Result{status: :failed, reason: :invalid_provider_response}} =
             Task.await(caller)
  end

  test "rejects mixed output that exceeds the accumulated bound before tool submission" do
    session =
      start_session(
        tools: [tool_descriptor()],
        executor: Vxpipe.AgentRuntime.TestExecutor,
        maximum_output_bytes: 3
      )

    caller = request(session, "Check an account", "req_output_limit_tool")
    release_pending_context("req_output_limit_tool")
    assert_receive {:model_provider_process, provider, _request}

    reply_with_tools(provider, [tool_call("call_1")], "four")

    assert {:ok, %Result{status: :failed, reason: :output_too_large}} = Task.await(caller)
    refute_receive {:tool_submitted, _executor, _identity, _arguments, _context, _call_id}
  end

  test "rejects a terminal response that exceeds the accumulated output bound" do
    session = start_session(maximum_output_bytes: 4)
    caller = request(session, "Say something", "req_output_limit_final")
    release_pending_context("req_output_limit_final")
    assert_receive {:model_provider_process, provider, _request}

    {:ok, response} = ModelResponse.new(text: "hello")
    send(provider, {:test_model_response, {:ok, response}})

    assert {:ok, %Result{status: :failed, reason: :output_too_large}} = Task.await(caller)
  end

  defp start_session(options) do
    defaults = [
      instructions: "Be concise",
      model_provider: Vxpipe.AgentRuntime.TestModelProvider,
      model: %{mode: :scripted, test_owner: self()},
      tools: [],
      executor: nil,
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

  defp reply_with_tools(provider, calls, text \\ "") do
    {:ok, response} = ModelResponse.new(text: text, tool_calls: calls)
    send(provider, {:test_model_response, {:ok, response}})
  end

  defp tool_call(id, name \\ "check_balance", arguments \\ %{}) do
    {:ok, call} = ToolCall.new(id: id, name: name, arguments: arguments)
    call
  end

  defp tool_descriptor do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: "check_balance",
        description: "Check an account balance",
        input_schema: %{"type" => "object", "additionalProperties" => false},
        binding: %{test_owner: self(), identity: :balance, submission: {:accepted, :blocking}}
      )

    descriptor
  end
end
