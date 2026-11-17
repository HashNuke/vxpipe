defmodule Vxpipe.AgentRuntime.EngineObservationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Input, ModelResponse, Session}

  test "retains an engine fact once without generating and preserves its exact text" do
    session = start_session()

    fact =
      "Engine supplied completion\n" <>
        JSON.encode!(%{
          "outcome" => %{"status" => "completed", "result" => "世界\nquoted \"value\""}
        })

    correlation = %{observation_id: "completion-one"}
    assert :ok = Session.record_engine(session, fact, correlation)
    assert :ok = Session.record_engine(session, fact, correlation)
    assert :ok = Session.record_engine(session, "Cannot rewrite the original fact", correlation)
    assert {:ok, true} = Session.durable?(session, correlation)
    assert :ok = Session.discard(session, [correlation])
    assert Session.status(session) == :idle
    refute_received {:model_stream_process, _, _}

    task =
      Task.async(fn -> Session.request(session, "human resumed", %{request_id: "resumed"}) end)

    assert_receive {:model_stream_process, provider, request}

    assert Enum.map(request.messages, &{&1.role, &1.origin, &1.content}) == [
             {:system, nil, "Test policy"},
             {:user, :engine, fact},
             {:user, :caller, "human resumed"}
           ]

    finish(provider, task)
  end

  test "records a completion before one typed timeout continuation without changing either message" do
    session = start_session()
    fact = "Actual native completion payload"
    assert :ok = Session.record_engine(session, fact, %{observation_id: "expired-idle"})
    {:ok, timeout} = Input.platform(:idle_timeout, %{}, :listener)
    task = Task.async(fn -> Session.continue(session, timeout, %{request_id: "timeout"}) end)
    assert_receive {:model_stream_process, provider, request}
    assert [fact_message, timeout_message] = Enum.take(request.messages, -2)
    assert fact_message.origin == :engine
    assert fact_message.content == fact
    assert timeout_message.origin == :engine
    assert timeout_message.content == Input.encode(timeout)
    finish(provider, task)
    refute_received {:model_stream_process, _, _}
  end

  test "cannot append into an active request or across unsettled speech" do
    session = start_session()
    correlation = %{request_id: "origin"}
    task = Task.async(fn -> Session.request(session, "human", correlation) end)
    assert_receive {:model_stream_process, provider, _request}
    assert {:error, :busy} = Session.record_engine(session, "fact", %{observation_id: "queued"})
    finish(provider, task)
    assert {:error, :busy} = Session.record_engine(session, "fact", %{observation_id: "queued"})
    assert :ok = Session.settle_output(session, correlation, nil)
    assert :ok = Session.record_engine(session, "fact", %{observation_id: "queued"})
  end

  test "rejects caller attribution and invalid or unbounded observations" do
    session = start_session()
    {:ok, caller} = Input.participant("human", "not an engine fact", :listener)

    assert {:error, :invalid_origin} =
             Session.record_engine(session, caller, %{observation_id: "forged"})

    assert {:error, :invalid_input} =
             Session.record_engine(session, "", %{observation_id: "empty"})

    assert {:error, :invalid_input} =
             Session.record_engine(session, " \n", %{observation_id: "blank"})

    assert {:error, :input_too_large} =
             Session.record_engine(session, String.duplicate("x", 65_537), %{
               observation_id: "large"
             })

    assert {:error, :invalid_input} =
             Session.record_engine(session, <<255>>, %{observation_id: "utf8"})

    assert {:error, :invalid_correlation} = Session.record_engine(session, "fact", %{})
    assert {:error, :invalid_correlation} = Session.record_engine(session, "fact", nil)
    assert Session.status(session) == :idle
    refute_received {:model_stream_process, _, _}
  end

  defp start_session do
    start_supervised!(
      {Session,
       instructions: "Test policy",
       history_mode: :host_settled,
       reply_protocol: :mode_message_v1,
       model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
       model: %{test_owner: self()},
       pending_context_source:
         {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
       event_destination: self()}
    )
  end

  defp finish(provider, task) do
    {:ok, response} = ModelResponse.new(text: ~s({"agent_mode":"listener","message":null}))
    send(provider, {:test_stream_response, {:ok, response}})
    assert {:ok, %{status: :completed}} = Task.await(task)
  end
end
