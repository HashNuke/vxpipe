defmodule Vxpipe.AgentRuntime.ConversationDiscardTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    PendingInvocation,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "discards a completed caller exchange selected by correlation" do
    session = start_session([])
    correlation = %{request_id: "req_discard_caller"}

    caller = request(session, "old topic", correlation)
    {provider, _request} = release_generation(correlation, [])
    reply_with_text(provider, "old answer")

    assert {:ok, %Result{status: :completed}} = Task.await(caller)
    assert {:ok, false} = Session.durable?(session, correlation)
    assert :ok = Session.discard(session, [correlation])

    next_correlation = %{request_id: "req_after_discard"}
    next_caller = request(session, "new topic", next_correlation)
    {next_provider, next_request} = release_generation(next_correlation, [])

    assert Enum.map(next_request.messages, & &1.role) == [:system, :user]
    reply_with_text(next_provider, "new answer")
    assert {:ok, %Result{status: :completed}} = Task.await(next_caller)
  end

  test "preserves an accepted tool exchange while discarding its final answer" do
    session = start_session([tool_descriptor()])
    correlation = %{request_id: "req_discard_tool"}

    caller = request(session, "check my balance", correlation)
    {provider, _request} = release_generation(correlation, [])
    reply_with_tool(provider)

    assert_receive {:tool_submitted, _executor, :balance, _arguments, ^correlation, "tool_call_1"}

    pending = pending_invocation()
    {acknowledgement_provider, _request} = release_generation(correlation, [pending])
    reply_with_text(acknowledgement_provider, "I am checking now.")
    assert {:ok, %Result{status: :completed}} = Task.await(caller)

    assert {:ok, true} = Session.durable?(session, correlation)
    assert :ok = Session.discard(session, [correlation])

    next_correlation = %{request_id: "req_after_tool_discard"}
    next_caller = request(session, "what are the card rules?", next_correlation)
    {next_provider, request} = release_generation(next_correlation, [pending])

    assert Enum.map(request.messages, & &1.role) == [:system, :user, :assistant, :tool, :user]
    assert running_invocation_ids(request) == ["tool_call_1"]
    refute Enum.any?(request.messages, &(&1.content == "I am checking now."))

    reply_with_text(next_provider, "The rules are available.")
    assert {:ok, %Result{status: :completed}} = Task.await(next_caller)
  end

  test "retains a private engine observation while discarding its interrupted answer" do
    session = start_session([])
    correlation = %{request_id: "req_discard_completion"}

    continuation =
      Task.async(fn ->
        Session.continue(session, "The balance tool completed with 23 dollars.", correlation)
      end)

    {provider, _request} = release_generation(correlation, [])
    reply_with_text(provider, "Your balance is 23 dollars.")
    assert {:ok, %Result{status: :completed}} = Task.await(continuation)

    assert {:ok, true} = Session.durable?(session, correlation)
    assert :ok = Session.discard(session, [correlation])

    next_correlation = %{request_id: "req_after_completion_discard"}
    caller = request(session, "thanks", next_correlation)
    {next_provider, request} = release_generation(next_correlation, [])

    assert Enum.map(request.messages, & &1.role) == [:system, :user, :user]
    assert Enum.at(request.messages, 1).origin == :engine

    assert Enum.at(request.messages, 1).content ==
             "The balance tool completed with 23 dollars."

    refute Enum.any?(request.messages, &(&1.content == "Your balance is 23 dollars."))

    reply_with_text(next_provider, "You are welcome.")
    assert {:ok, %Result{status: :completed}} = Task.await(caller)
  end

  defp start_session(tools) do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       model_provider: Vxpipe.AgentRuntime.TestModelProvider,
       model: %{mode: :scripted, test_owner: self()},
       tools: tools,
       executor: if(tools == [], do: nil, else: Vxpipe.AgentRuntime.TestExecutor),
       maximum_model_rounds: 2,
       pending_context_source:
         {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
       event_destination: self()}
    )
  end

  defp request(session, text, correlation) do
    Task.async(fn -> Session.request(session, text, correlation) end)
  end

  defp release_generation(correlation, pending_invocations) do
    assert_receive {:pending_context_requested, source, ^correlation, 1_000}
    send(source, {:release, {:ok, pending_invocations}})
    assert_receive {:model_provider_process, provider, request}
    {provider, request}
  end

  defp reply_with_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
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

  defp running_invocation_ids(request) do
    request.messages
    |> Enum.filter(&(&1.role == :tool))
    |> Enum.map(&JSON.decode!(&1.content))
    |> Enum.filter(&(&1["status"] == "running"))
    |> Enum.map(& &1["invocation_id"])
  end

  defp pending_invocation do
    {:ok, invocation} =
      PendingInvocation.new(
        invocation_id: "tool_call_1",
        tool_name: "check_balance",
        status: :running,
        conversation_mode: :non_blocking,
        source_turn_id: "turn_1"
      )

    invocation
  end

  defp tool_descriptor do
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
        binding: %{
          test_owner: self(),
          identity: :balance,
          submission: {:accepted, :non_blocking}
        }
      )

    descriptor
  end
end
