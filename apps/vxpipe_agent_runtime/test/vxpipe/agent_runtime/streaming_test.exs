defmodule Vxpipe.AgentRuntime.StreamingTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Event, ModelResponse, Result, Session}

  test "emits ordered provisional text and commits only the final response" do
    session = start_session([])
    caller = request(session, "Hello", "req_stream_1")
    release_pending_context("req_stream_1")
    assert_receive {:model_stream_process, provider, _request}

    send(provider, {:test_stream_delta, "Hel"})

    assert_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "Hel"}} = event}

    refute inspect(event) =~ "Hel"

    send(provider, {:test_stream_delta, "lo"})

    assert_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "lo"}}}

    reply_with_text(provider, "Hello")

    assert {:ok, %Result{status: :completed, output: "Hello"}} = Task.await(caller)
    refute_receive {:unexpected_buffered_generation, _provider, _request}
  end

  test "suppresses deltas after cancellation" do
    session = start_session([])
    caller = request(session, "Tell me a story", "req_stream_cancel")
    release_pending_context("req_stream_cancel")
    assert_receive {:model_stream_process, provider, _request}
    provider_monitor = Process.monitor(provider)

    send(provider, {:test_stream_delta, "Once"})

    assert_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "Once"}}}

    assert :ok = Session.cancel(session)
    assert {:ok, %Result{status: :cancelled}} = Task.await(caller)
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider, _reason}

    send(provider, {:test_stream_delta, " upon a time"})

    refute_receive {:agent_runtime_event,
                    %Event{kind: :text_delta, data: %{text: " upon a time"}}}
  end

  test "rejects streamed text beyond the output byte bound before emitting it" do
    session = start_session(maximum_output_bytes: 4)
    caller = request(session, "Hello", "req_stream_bytes")
    release_pending_context("req_stream_bytes")
    assert_receive {:model_stream_process, provider, _request}

    send(provider, {:test_stream_delta, "hello"})

    refute_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "hello"}}}

    {:ok, response} =
      ModelResponse.new(
        text: "hello",
        usage: %{input_tokens: 5, output_tokens: 2},
        provider_metadata: %{request_id: "provider-oversized-output"}
      )

    send(provider, {:test_stream_response, {:ok, response}})

    assert_receive {:agent_runtime_event,
                    %Event{
                      kind: :model_usage,
                      data: %{
                        usage: %{input_tokens: 5, output_tokens: 2},
                        provider_metadata: %{request_id: "provider-oversized-output"}
                      }
                    }}

    assert {:ok, %Result{status: :failed, reason: :output_too_large}} = Task.await(caller)
  end

  test "rejects excessive stream events without emitting beyond the configured count" do
    session = start_session(maximum_stream_events_per_round: 1)
    caller = request(session, "Hello", "req_stream_events")
    release_pending_context("req_stream_events")
    assert_receive {:model_stream_process, provider, _request}

    send(provider, {:test_stream_delta, "a"})
    assert_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "a"}}}

    send(provider, {:test_stream_delta, "b"})
    refute_receive {:agent_runtime_event, %Event{kind: :text_delta, data: %{text: "b"}}}

    reply_with_text(provider, "ab")

    assert {:ok, %Result{status: :failed, reason: :stream_event_limit}} = Task.await(caller)
  end

  defp start_session(options) do
    defaults = [
      instructions: "Be concise",
      model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
      model: %{test_owner: self()},
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

  defp reply_with_text(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_stream_response, {:ok, response}})
  end
end
