defmodule Vxpipe.AgentRuntime.DialogueSessionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Event, Input, ModelResponse, Session}

  test "buffers control JSON and returns one typed result for every ordinary input origin" do
    session = start_session()
    {:ok, human} = Input.participant("human", "hello", :listener)
    {:ok, overlap} = Input.participant("human", "actually Friday", :speaker)
    {:ok, greeting} = Input.platform(:greeting_request, %{}, :listener)
    {:ok, idle} = Input.platform(:idle_timeout, %{}, :listener)

    for {input, origin} <- [
          {human, :caller},
          {overlap, :caller},
          {greeting, :engine},
          {idle, :engine},
          {"completed tool", :engine}
        ] do
      correlation = %{request_id: make_ref()}

      task =
        Task.async(fn ->
          case origin do
            :caller -> Session.request(session, input, correlation)
            :engine -> Session.continue(session, input, correlation)
          end
        end)

      assert_receive {:model_stream_process, provider, request}
      assert request.reply_protocol == :mode_message_v1
      send(provider, {:test_stream_delta, ~s({"agent_mode":"speaker",)})
      text = ~s({"agent_mode":"speaker","message":"Hello"})
      reply(provider, text)

      assert {:ok,
              %{
                status: :completed,
                output: nil,
                dialogue: %{agent_mode: :speaker, message: "Hello"}
              }} = Task.await(task)

      refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
      assert :ok = Session.settle_output(session, correlation, nil)
    end
  end

  test "valid silence succeeds while malformed and incomplete replies fail" do
    session = start_session()

    for {text, expected} <- [
          {~s({"agent_mode":"listener","message":null}), :completed},
          {~s({"agent_mode":"listener","message":"okay"}), :completed},
          {~s({"agent_mode":"speaker","message":null}), :failed},
          {~s({"agent_mode":"listener","message":), :failed},
          {"Sorry, I cannot", :failed}
        ] do
      correlation = %{request_id: make_ref()}
      task = Task.async(fn -> Session.request(session, "hello", correlation) end)
      assert_receive {:model_stream_process, provider, _request}
      reply(provider, text)
      assert {:ok, %{status: ^expected}} = Task.await(task)
      refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
      assert :ok = Session.settle_output(session, correlation, nil)
    end
  end

  test "failed streams never leak their partial structured output" do
    session = start_session()
    task = Task.async(fn -> Session.request(session, "hello", %{request_id: "failed"}) end)
    assert_receive {:model_stream_process, provider, _request}
    send(provider, {:test_stream_delta, ~s({"agent_mode":"speaker","message":"Hi)})
    send(provider, {:test_stream_response, {:error, :upstream_failed}})
    assert {:ok, %{status: :failed}} = Task.await(task)
    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
  end

  test "buffering remains bounded and cancellation leaves admitted input available" do
    session = start_session(maximum_output_bytes: 60)
    correlation = %{request_id: "cancelled-structured"}
    task = Task.async(fn -> Session.request(session, "keep this human input", correlation) end)
    assert_receive {:model_stream_process, provider, _request}
    monitor = Process.monitor(provider)
    send(provider, {:test_stream_delta, ~s({"agent_mode":"speaker",)})
    assert :ok = Session.cancel(session)
    assert {:ok, %{status: :cancelled}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}
    assert :ok = Session.settle_output(session, correlation, nil)
    correlation = %{request_id: "oversized-structured"}
    task = Task.async(fn -> Session.request(session, "next", correlation) end)
    assert_receive {:model_stream_process, provider, request}
    assert Enum.any?(request.messages, &(&1.content == "keep this human input"))
    reply(provider, JSON.encode!(%{agent_mode: "speaker", message: String.duplicate("a", 61)}))
    assert {:ok, %{status: :failed, reason: :output_too_large}} = Task.await(task)
    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
  end

  test "an unfinished object reaches the request deadline without producing speech" do
    session = start_session(request_timeout_ms: 100)
    task = Task.async(fn -> Session.request(session, "hello", %{request_id: "timeout"}) end)
    assert_receive {:model_stream_process, provider, _}
    monitor = Process.monitor(provider)
    send(provider, {:test_stream_delta, ~s({"agent_mode":"speaker",)})
    assert {:ok, %{status: :failed, reason: :request_timeout}} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}
    refute_received {:agent_runtime_event, %Event{kind: :text_delta}}
  end

  defp start_session(options \\ []) do
    defaults = [
      instructions: "Be concise",
      history_mode: :host_settled,
      reply_protocol: :mode_message_v1,
      model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
      model: %{test_owner: self()},
      pending_context_source:
        {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
      event_destination: self()
    ]

    start_supervised!({Session, Keyword.merge(defaults, options)})
  end

  defp reply(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_stream_response, {:ok, response}})
  end
end
