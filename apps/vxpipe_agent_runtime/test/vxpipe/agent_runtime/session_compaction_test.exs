defmodule Vxpipe.AgentRuntime.SessionCompactionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{CompactionResult, Event, ModelResponse, Result, Session}

  test "commits one safe compaction before the conversational provider request" do
    session = start_session()
    complete_initial_exchange(session)

    caller = request(session, "second request", "second")
    assert_pending_context("second")
    assert_count(700)

    assert_receive {:input_tokens_counted, counter, protected_request}
    refute Enum.any?(protected_request.messages, &(&1.content == "first request"))
    send(counter, {:input_token_count, 300})

    assert_receive {:context_compaction_requested, compactor, compaction_request}
    assert Enum.any?(compaction_request.messages, &(&1.content == "first request"))

    {:ok, summary} =
      CompactionResult.new(
        summary: "The caller made a first request and received a first response.",
        usage: %{input_tokens: 30, output_tokens: 12},
        provider_metadata: %{model: "same:pinned-model"}
      )

    send(compactor, {:context_compaction_result, {:ok, summary}})
    assert_count(350)

    assert_receive {:agent_runtime_event,
                    %Event{
                      kind: :context_compaction_usage,
                      correlation: %{request_id: "second"},
                      data: %{
                        outcome: :succeeded,
                        usage: %{input_tokens: 30, output_tokens: 12},
                        provider_metadata: %{model: "same:pinned-model"}
                      }
                    } = event}

    assert event.data == %{
             outcome: :succeeded,
             usage: %{input_tokens: 30, output_tokens: 12},
             provider_metadata: %{model: "same:pinned-model"}
           }

    refute inspect(event) =~ "same:pinned-model"

    assert_receive {:model_provider_process, provider, model_request}
    assert Enum.any?(model_request.messages, &(&1.origin == :derived_summary))
    assert List.last(model_request.messages).content == "second request"
    reply(provider, "second response")

    assert {:ok, %Result{status: :completed, output: "second response"}} = Task.await(caller)

    third = request(session, "third request", "third")
    assert_pending_context("third")
    assert_count(500)
    assert_receive {:model_provider_process, provider, third_request}
    assert Enum.any?(third_request.messages, &(&1.origin == :derived_summary))
    refute Enum.any?(third_request.messages, &(&1.content == "first request"))
    reply(provider, "third response")
    assert {:ok, %Result{status: :completed}} = Task.await(third)
  end

  test "reports incurred compaction usage when the rebuilt context remains too large" do
    session = start_session()
    complete_initial_exchange(session)

    caller = request(session, "second request", "rejected-summary")
    assert_pending_context("rejected-summary")
    assert_count(700)

    assert_receive {:input_tokens_counted, counter, _protected_request}
    send(counter, {:input_token_count, 300})
    assert_receive {:context_compaction_requested, compactor, _compaction_request}

    {:ok, summary} =
      CompactionResult.new(
        summary: "This valid summary still leaves too much context.",
        usage: %{input_tokens: 30, output_tokens: 12},
        provider_metadata: %{request_id: "compaction-rejected-1"}
      )

    send(compactor, {:context_compaction_result, {:ok, summary}})
    assert_count(450)

    assert_receive {:agent_runtime_event,
                    %Event{
                      kind: :context_compaction_usage,
                      correlation: %{request_id: "rejected-summary"},
                      data: %{
                        outcome: :failed,
                        usage: %{input_tokens: 30, output_tokens: 12},
                        provider_metadata: %{request_id: "compaction-rejected-1"}
                      }
                    }}

    assert {:ok, %Result{status: :failed, reason: :compacted_context_too_large}} =
             Task.await(caller)
  end

  test "terminating the session terminates its in-flight compactor" do
    session = start_session()
    complete_initial_exchange(session)

    caller =
      Task.async(fn ->
        try do
          Session.request(session, "second request", %{request_id: "terminating"})
        catch
          :exit, _reason -> :session_stopped
        end
      end)

    assert_pending_context("terminating")
    assert_count(700)
    assert_receive {:input_tokens_counted, counter, _protected_request}
    send(counter, {:input_token_count, 300})
    assert_receive {:context_compaction_requested, compactor, _request}

    monitor = Process.monitor(compactor)
    GenServer.stop(session, :shutdown)

    assert_receive {:DOWN, ^monitor, :process, ^compactor, _reason}
    assert Task.await(caller) == :session_stopped
  end

  defp start_session do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       model_provider: Vxpipe.AgentRuntime.TestModelProvider,
       model: %{mode: :scripted, test_owner: self()},
       pending_context_source:
         {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
       context_compaction: [
         enabled: true,
         context_window_tokens: 1_000,
         output_reserve_tokens: 200,
         recent_entries: 1,
         input_token_counter:
           {Vxpipe.AgentRuntime.TestInputTokenCounter, %{owner: self(), result: :manual}},
         input_token_timeout_ms: 1_000,
         compactor: {Vxpipe.AgentRuntime.TestContextCompactor, %{owner: self(), result: :manual}},
         compactor_timeout_ms: 1_000
       ],
       event_destination: self()}
    )
  end

  defp complete_initial_exchange(session) do
    caller = request(session, "first request", "first")
    assert_pending_context("first")
    assert_count(500)
    assert_receive {:model_provider_process, provider, request}
    refute Enum.any?(request.messages, &(&1.origin == :derived_summary))
    reply(provider, "first response")
    assert {:ok, %Result{status: :completed}} = Task.await(caller)

    assert :ok =
             Session.record_assistant(session, "transition message", %{request_id: "transition"})
  end

  defp request(session, content, request_id) do
    Task.async(fn -> Session.request(session, content, %{request_id: request_id}) end)
  end

  defp assert_pending_context(request_id) do
    assert_receive {:pending_context_requested, _source, %{request_id: ^request_id}, 1_000}
  end

  defp assert_count(count) do
    assert_receive {:input_tokens_counted, counter, _request}
    send(counter, {:input_token_count, count})
  end

  defp reply(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
  end
end
