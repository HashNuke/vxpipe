defmodule Vxpipe.AgentRuntime.PreflightCancelTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{ModelResponse, Result, Session, ToolCall, ToolDescriptor}

  alias Vxpipe.AgentRuntime.TestPreflightExecutor

  test "a blocking preflight before submission stays cancellable" do
    session =
      start_supervised!(
        {Session,
         [
           instructions: "Be concise",
           model_provider: Vxpipe.AgentRuntime.TestModelProvider,
           model: %{mode: :scripted, test_owner: self()},
           tools: [tool_descriptor("check_balance", :block)],
           executor: TestPreflightExecutor,
           maximum_model_rounds: 2,
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
           event_destination: self()
         ]}
      )

    task =
      Task.async(fn -> Session.request(session, "Check", %{request_id: "preflight-cancel"}) end)

    assert_receive {:pending_context_requested, source, %{request_id: "preflight-cancel"}, 1_000}
    send(source, {:release, {:ok, []}})
    assert_receive {:model_provider_process, provider, _request}

    {:ok, response} =
      ModelResponse.new(text: "checking", tool_calls: [tool_call("call-1", "check_balance")])

    send(provider, {:test_model_response, {:ok, response}})

    # Worker is now blocked in preflight, before begin_submission. Cancel must
    # succeed immediately instead of deadlocking waiting for a commit.
    assert_receive :preflight_entered, 1_000
    assert :ok = Session.cancel(session, 500)
    assert {:ok, %Result{status: :cancelled}} = Task.await(task, 1_000)
    refute_received :submit_called
  end

  for reason <- [:unavailable, :caller_answer_pending] do
    test "a #{reason} preflight rejection never reaches submit and corrects privately" do
      session =
        start_supervised!(
          {Session,
           [
             instructions: "Be concise",
             model_provider: Vxpipe.AgentRuntime.TestModelProvider,
             model: %{mode: :scripted, test_owner: self()},
             tools: [tool_descriptor("check_balance", unquote(reason))],
             executor: TestPreflightExecutor,
             maximum_model_rounds: 2,
             pending_context_source:
               {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
             event_destination: self()
           ]},
          id: :rejecting_preflight_session
        )

      task =
        Task.async(fn -> Session.request(session, "Check", %{request_id: "preflight-reject"}) end)

      assert_receive {:pending_context_requested, source, %{request_id: "preflight-reject"},
                      1_000}

      send(source, {:release, {:ok, []}})
      assert_receive {:model_provider_process, provider, _request}

      {:ok, response} =
        ModelResponse.new(text: "checking", tool_calls: [tool_call("call-1", "check_balance")])

      send(provider, {:test_model_response, {:ok, response}})

      # Correction round must observe the private rejection.
      assert_receive {:pending_context_requested, source2, %{request_id: "preflight-reject"},
                      1_000}

      send(source2, {:release, {:ok, []}})
      assert_receive {:model_provider_process, provider2, correction}
      results = Enum.filter(correction.messages, &(&1.role == :tool))
      assert [%{content: content}] = results

      assert JSON.decode!(content) == %{
               "status" => "rejected",
               "reason" => Atom.to_string(unquote(reason))
             }

      send(provider2, {:test_model_response, {:ok, elem(ModelResponse.new(text: "done"), 1)}})
      assert {:ok, %Result{status: :completed}} = Task.await(task, 1_000)
      refute_received :submit_called
    end
  end

  defp tool_descriptor(name, identity) do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: name,
        description: "Check an account value",
        input_schema: %{
          "type" => "object",
          "properties" => %{"account_id" => %{"type" => "string"}},
          "required" => ["account_id"],
          "additionalProperties" => false
        },
        binding: %{test_owner: self(), identity: identity, submission: {:accepted, :non_blocking}}
      )

    descriptor
  end

  defp tool_call(id, name) do
    {:ok, call} = ToolCall.new(id: id, name: name, arguments: %{"account_id" => "account_1"})
    call
  end
end
