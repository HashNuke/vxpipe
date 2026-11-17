defmodule Vxpipe.AgentRuntime.SettledHistoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Input, Message, ModelResponse, Session}

  test "keeps admitted input, waits for settlement and retains only supported assistant text" do
    session = start_session()
    {:ok, input} = Input.participant("human-1", "hello", :listener)
    first = %{request_id: "first"}
    task = Task.async(fn -> Session.request(session, input, first) end)
    assert_receive {:model_provider_process, provider, request}
    prefix = request.messages
    reply(provider, "x y z")
    assert {:ok, %{output: "x y z"}} = Task.await(task)
    assert {:error, :busy} = Session.request(session, "too soon", %{})

    assert {:ok, spoken} = Message.spoken_assistant("agent-1", "x y", :speaker)
    assert :ok = Session.settle_output(session, first, spoken)
    assert {:error, :stale_settlement} = Session.settle_output(session, first, spoken)

    task = Task.async(fn -> Session.request(session, "next", %{request_id: "second"}) end)
    assert_receive {:model_provider_process, provider, next}
    assert Enum.take(next.messages, length(prefix)) == prefix
    assert Enum.at(next.messages, length(prefix)) == spoken
    refute Enum.any?(next.messages, &(&1.content == "x y z"))

    assert JSON.decode!(spoken.content) == %{
             "type" => "participant_message",
             "participant_id" => "agent-1",
             "agent_mode" => "speaker",
             "message" => "x y"
           }

    reply(provider, "done")
    Task.await(task)
    assert :ok = Session.settle_output(session, %{request_id: "second"}, nil)
  end

  test "cancelled generation preserves admitted input and zero or unknown delivery adds no speech" do
    session = start_session()
    correlation = %{request_id: "cancelled"}
    {:ok, input} = Input.participant("human-2", "actually Friday", :speaker)
    task = Task.async(fn -> Session.request(session, input, correlation) end)
    assert_receive {:model_provider_process, _provider, request}
    admitted = List.last(request.messages)
    assert :ok = Session.cancel(session)
    assert {:ok, %{status: :cancelled}} = Task.await(task)
    assert :ok = Session.discard(session, [correlation])
    assert {:error, :stale_settlement} = Session.settle_output(session, %{}, nil)
    assert :ok = Session.settle_output(session, correlation, nil)

    task = Task.async(fn -> Session.request(session, "new input", %{request_id: "next"}) end)
    assert_receive {:model_provider_process, provider, next}
    assert next.messages == [Message.system("Be concise"), admitted, Message.user("new input")]
    reply(provider, "okay")
    Task.await(task)
  end

  test "fixed greeting is staged without a model round and only settled speech appends" do
    session = start_session()
    correlation = %{request_id: "greeting"}
    assert :ok = Session.record_assistant(session, "Welcome to the call", correlation)
    refute_received {:model_provider_process, _, _}
    assert {:error, :busy} = Session.request(session, "hello", %{})
    assert :ok = Session.settle_output(session, correlation, nil)
    task = Task.async(fn -> Session.request(session, "hello", %{request_id: "after"}) end)
    assert_receive {:model_provider_process, provider, request}
    assert request.messages == [Message.system("Be concise"), Message.user("hello")]
    reply(provider, "Hello")
    Task.await(task)
  end

  test "rejects invalid spoken history and settlement while inference is active" do
    assert {:error, :invalid_message} = Message.spoken_assistant("", "hello", :speaker)
    assert {:error, :invalid_message} = Message.spoken_assistant("agent", " ", :speaker)
    assert {:error, :invalid_message} = Message.spoken_assistant("agent", <<255>>, :speaker)
    assert {:error, :invalid_message} = Message.spoken_assistant("agent", "hello", :other)
    session = start_session()
    task = Task.async(fn -> Session.request(session, "hello", %{request_id: "busy"}) end)
    assert_receive {:model_provider_process, provider, _request}
    assert {:error, :busy} = Session.settle_output(session, %{request_id: "busy"}, nil)
    reply(provider, "hi")
    Task.await(task)
  end

  test "settlement respects configured output bytes rather than the smaller input limit" do
    session = start_session()
    text = String.duplicate("\"", 70_000)
    task = Task.async(fn -> Session.request(session, "long answer", %{request_id: "long"}) end)
    assert_receive {:model_provider_process, provider, _request}
    reply(provider, text)
    Task.await(task)
    assert {:ok, spoken} = Message.spoken_assistant("agent", text, :speaker)
    assert :ok = Session.settle_output(session, %{request_id: "long"}, spoken)
  end

  test "seeds transferred supported speech using output bounds without parsing legacy input" do
    text = String.duplicate("\"", 70_000)
    {:ok, spoken} = Message.spoken_assistant("previous-agent", text, :speaker)
    legacy = Message.user(~s({"type":"platform_event"}))
    session = start_session(initial_messages: [legacy, spoken])
    task = Task.async(fn -> Session.request(session, "hello", %{request_id: "transferred"}) end)
    assert_receive {:model_provider_process, provider, request}

    assert request.messages == [
             Message.system("Be concise"),
             legacy,
             spoken,
             Message.user("hello")
           ]

    reply(provider, "Hello")
    Task.await(task)
  end

  defp start_session(options \\ []) do
    start_supervised!(
      {Session,
       Keyword.merge(
         [
           instructions: "Be concise",
           history_mode: :host_settled,
           model_provider: Vxpipe.AgentRuntime.TestModelProvider,
           model: %{mode: :scripted, test_owner: self()},
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
           event_destination: self()
         ],
         options
       )}
    )
  end

  defp reply(provider, text) do
    {:ok, response} = ModelResponse.new(text: text)
    send(provider, {:test_model_response, {:ok, response}})
  end
end
