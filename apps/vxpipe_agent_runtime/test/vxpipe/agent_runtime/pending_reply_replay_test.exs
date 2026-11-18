defmodule Vxpipe.AgentRuntime.PendingReplyReplayTest do
  use ExUnit.Case, async: false

  alias Vxpipe.AgentRuntime.{
    Dialogue,
    DialogueWireServer,
    Input,
    Message,
    ModelResponse,
    PendingReplyReplay,
    Session
  }

  alias Vxpipe.AgentRuntime.Provider.ReqLLM, as: Provider
  alias Vxpipe.AgentRuntime.Provider.ReqLLM.ChatReasoningReplay
  alias ReqLLM.Message.ContentPart

  test "only source verified bounded unsigned replay can become a pending candidate" do
    {:ok, config} = Provider.new(model: "deepseek:deepseek-flash", api_key: "test-only")
    text = ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Café."})
    upstream = ReqLLM.Context.assistant(text)

    upstream = %{
      upstream
      | content: [ContentPart.thinking("private sentinel") | upstream.content]
    }

    {:ok, replay} = ChatReasoningReplay.capture(config.model, %{message: upstream}, text, [])
    {:ok, response} = ModelResponse.new(text: text, provider_replay: replay)
    dialogue = %Dialogue{agent_mode: :speaker, message: "Café."}
    opts = %{model: config, history_mode: :host_settled}
    candidate = PendingReplyReplay.prepare(response, dialogue, opts)
    assert %PendingReplyReplay{} = candidate
    refute inspect(candidate) =~ "private sentinel"
    refute :erlang.term_to_binary(candidate) =~ text
    {:ok, spoken} = Message.spoken_assistant("agent", "Café.", :speaker)
    rebound = PendingReplyReplay.settle(candidate, spoken)

    projected =
      ChatReasoningReplay.restore(ReqLLM.Context.assistant(spoken.content), rebound, config.model)

    assert Enum.any?(projected.content, &(&1.type == :thinking and &1.text == "private sentinel"))

    for invalid <- [
          Map.put(replay, "source_digest", "bad"),
          Map.put(replay, "model", "different"),
          Map.put(replay, "wire_model", "different"),
          Map.put(replay, "provider", "fireworks_ai"),
          Map.put(replay, "format", "google_parts_v1"),
          Map.put(replay, "signature", "opaque signature"),
          Map.put(replay, "reasoning", String.duplicate("x", 70_000)),
          Map.put(replay, "reasoning", <<255>>),
          Map.put(replay, "reasoning", nil),
          Map.put(replay, "reasoning", ""),
          Map.put(replay, "alternate_public", text)
        ] do
      assert is_nil(
               PendingReplyReplay.prepare(%{response | provider_replay: invalid}, dialogue, opts)
             )
    end

    assert is_nil(PendingReplyReplay.prepare(%{response | text: "changed"}, dialogue, opts))

    assert is_nil(
             PendingReplyReplay.prepare(response, dialogue, %{opts | history_mode: :generated})
           )
  end

  for streaming <- [false, true] do
    @tag capture_log: true
    test "stale and invalid settlements preserve only their own candidate streaming=#{streaming}" do
      {session, _tasks} = session(unquote(streaming))
      corr = %{request_id: "first"}
      assert {:ok, result} = Session.request(session, input("first"), corr)
      refute :erlang.term_to_binary(result) =~ "private sentinel"
      assert_receive {:encoded_request, _}
      events = drain_events([])
      assert events != []
      refute :erlang.term_to_binary(events) =~ "private sentinel"
      refute inspect(:sys.get_state(session)) =~ "private sentinel"
      assert %PendingReplyReplay{} = :sys.get_state(session).pending_replay
      {:ok, spoken} = Message.spoken_assistant("agent", "Hello.", :speaker)

      assert {:error, :stale_settlement} =
               Session.settle_output(session, %{request_id: "wrong"}, spoken)

      assert {:error, :invalid_message} =
               Session.settle_output(session, corr, %{
                 spoken
                 | provider_replay: %{"reasoning" => "injected"}
               })

      assert {:error, :busy} = Session.request(session, input("early"), %{request_id: "early"})
      assert :ok = Session.settle_output(session, corr, spoken)
      assert is_nil(:sys.get_state(session).pending_replay)
      assert {:error, :stale_settlement} = Session.settle_output(session, corr, spoken)
      assert {:ok, _} = Session.request(session, input("next"), %{request_id: "next"})
      assert_receive {:encoded_request, next}
      assistants = Enum.filter(next["messages"], &(&1["role"] == "assistant"))
      assert length(assistants) == 1
      assert hd(assistants)["reasoning_content"] == "private sentinel"
    end

    @tag capture_log: true
    test "already settled reasoning survives later cancellation and failure once streaming=#{streaming}" do
      {session, tasks} = session(unquote(streaming))
      first = %{request_id: "first"}
      assert {:ok, _} = Session.request(session, input("first"), first)
      assert_receive {:encoded_request, _}
      {:ok, spoken} = Message.spoken_assistant("agent", "Hello.", :speaker)
      assert :ok = Session.settle_output(session, first, spoken)

      original =
        Enum.find(:sys.get_state(session).conversation.messages, &(&1.role == :assistant))

      assert original.provider_replay != %{}
      second = %{request_id: "cancelled"}

      call =
        Task.Supervisor.async(tasks, fn -> Session.request(session, input("hold"), second) end)

      assert_receive {:encoded_request, _}
      assert_receive {:wire_waiting, responder}
      assert :ok = Session.cancel(session)
      assert {:ok, %{status: :cancelled}} = Task.await(call)
      send(responder, :release)
      assert :ok = Session.discard(session, [second])
      assert :ok = Session.settle_output(session, second, nil)
      failed = %{request_id: "failed"}
      assert {:ok, %{status: :failed}} = Session.request(session, input("invalid"), failed)
      assert_receive {:encoded_request, failed_wire}

      assert length(
               Enum.filter(
                 failed_wire["messages"],
                 &(&1["reasoning_content"] == "private sentinel")
               )
             ) == 1

      assert :ok = Session.discard(session, [failed])
      assert :ok = Session.settle_output(session, failed, nil)
      assert original in :sys.get_state(session).conversation.messages
      assert {:ok, _} = Session.request(session, input("recovered"), %{request_id: "recovered"})
      assert_receive {:encoded_request, recovered}
      assistants = Enum.filter(recovered["messages"], &(&1["role"] == "assistant"))
      assert length(assistants) == 1
      assert hd(assistants)["reasoning_content"] == "private sentinel"
      assert hd(assistants)["content"] == original.content
    end

    @tag capture_log: true
    test "cancelled and failed subsequent requests cannot reuse a discarded candidate streaming=#{streaming}" do
      {session, tasks} = session(unquote(streaming))
      first = %{request_id: "first"}
      assert {:ok, _} = Session.request(session, input("first"), first)
      assert_receive {:encoded_request, _}
      assert :ok = Session.settle_output(session, first, nil)
      assert is_nil(:sys.get_state(session).pending_replay)
      second = %{request_id: "second"}

      call =
        Task.Supervisor.async(tasks, fn -> Session.request(session, input("hold"), second) end)

      assert_receive {:encoded_request, _}
      assert_receive {:wire_waiting, responder}
      assert :ok = Session.cancel(session)
      assert {:ok, %{status: :cancelled}} = Task.await(call)
      send(responder, :release)
      assert is_nil(:sys.get_state(session).pending_replay)
      {:ok, spoken} = Message.spoken_assistant("agent", "Hello.", :speaker)
      assert :ok = Session.settle_output(session, second, spoken)
      failed = %{request_id: "failed"}
      assert {:ok, %{status: :failed}} = Session.request(session, input("invalid"), failed)
      assert_receive {:encoded_request, wire}
      refute JSON.encode!(wire) =~ "private sentinel"
      assert is_nil(:sys.get_state(session).pending_replay)
      assert :ok = Session.settle_output(session, failed, spoken)
      assert :ok = Session.record_assistant(session, "Hello.", %{request_id: "fixed"})
      assert :ok = Session.settle_output(session, %{request_id: "fixed"}, spoken)
      assert {:ok, _} = Session.request(session, input("final"), %{request_id: "final"})
      assert_receive {:encoded_request, final}
      refute JSON.encode!(final) =~ "private sentinel"
    end
  end

  defp session(streaming) do
    owner = self()

    url =
      DialogueWireServer.start(owner, fn body ->
        last = List.last(body["messages"])
        text = JSON.decode!(last["content"])["message"]

        if text == "hold" do
          send(owner, {:wire_waiting, self()})

          receive do
            :release -> :ok
          after
            5_000 -> raise "fixture release timed out"
          end
        end

        content =
          if text == "invalid",
            do: "not dialogue",
            else: ~s({"type":"participant_message","participant_id":"agent","agent_mode":"speaker","message":"Hello."})

        message = %{role: "assistant", content: content, reasoning_content: "private sentinel"}

        choice =
          Map.put(
            %{index: 0, finish_reason: "stop"},
            if(streaming, do: :delta, else: :message),
            message
          )

        payload = JSON.encode!(%{id: "reply", model: body["model"], choices: [choice]})

        if streaming,
          do: {"text/event-stream", "data: " <> payload <> "\n\ndata: [DONE]\n\n"},
          else: {"application/json", payload}
      end)

    {:ok, config} =
      Provider.new(
        model: "deepseek:deepseek-flash",
        api_key: "test-only",
        streaming: streaming,
        generation_options: [base_url: url]
      )

    session =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         history_mode: :host_settled,
         reply_protocol: :mode_message_v1,
         model_provider: Provider,
         model: config,
         executor: Vxpipe.AgentRuntime.TestExecutor,
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
         event_destination: self()}
      )

    tasks = start_supervised!({Task.Supervisor, []})
    {session, tasks}
  end

  defp input(text) do
    {:ok, input} = Input.participant("human", text, :listener)
    input
  end

  defp drain_events(acc) do
    receive do
      {:agent_runtime_event, %Vxpipe.AgentRuntime.Event{} = event} -> drain_events([event | acc])
    after
      0 -> acc
    end
  end
end
