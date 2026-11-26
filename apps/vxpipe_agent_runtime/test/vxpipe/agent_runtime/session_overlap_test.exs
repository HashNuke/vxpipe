defmodule Vxpipe.AgentRuntime.SessionOverlapTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{Message, Result, Session}

  defp speaker(text) do
    JSON.encode!(%{
      "type" => "participant_message",
      "participant_id" => "agent",
      "agent_mode" => "speaker",
      "message" => text
    })
  end

  defp listener do
    JSON.encode!(%{
      "type" => "participant_message",
      "participant_id" => "agent",
      "agent_mode" => "listener",
      "message" => nil
    })
  end

  test "structured completion overlaps earlier audio while ordinary requests keep the gate" do
    session = start_host_settled_session()

    first = Task.async(fn -> Session.request(session, "first", %{request_id: "overlap-a"}) end)
    assert_receive {:model_stream_process, first_provider, _request}

    send(
      first_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: speaker("first answer")), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(first)

    # Ordinary caller request while A outstanding keeps the original gate.
    assert {:error, :busy} = Session.request(session, "second", %{request_id: "overlap-ordinary"})

    # Structured completion via the tool-result protocol may run during earlier audio.
    second =
      Task.async(fn ->
        Session.continue_tool_result(session, "tool finished", %{request_id: "overlap-b"}, 2_000)
      end)

    assert_receive {:model_stream_process, second_provider, overlap_request}
    # A's input must precede B's input in the model conversation.
    contents = Enum.map(overlap_request.messages, & &1.content)
    assert Enum.any?(contents, &String.contains?(&1, "first"))

    send(
      second_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: listener()), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(second)
  end

  test "a fixed greeting heard during a private request precedes that request in history" do
    session = start_host_settled_session()
    greeting = %{request_id: "fixed"}
    saved = %{request_id: "outcome"}
    assert :ok = Session.record_assistant(session, "Welcome.", greeting)
    worker = Task.async(fn -> Session.continue_tool_result(session, "saved", saved, 2000) end)
    assert_receive {:model_stream_process, provider, _}
    {:ok, heard} = Message.spoken_assistant("agent", "Welcome.", :speaker)
    assert :ok = Session.settle_output(session, greeting, heard)
    {:ok, response} = Vxpipe.AgentRuntime.ModelResponse.new(text: listener())
    send(provider, {:test_stream_response, {:ok, response}})
    Task.await(worker)
    assert :ok = Session.settle_output(session, saved, nil)
    next = Task.async(fn -> Session.request(session, "hello", %{request_id: "hello"}) end)
    assert_receive {:model_stream_process, provider, request}
    assert [_, ^heard, %{content: "saved"}, %{content: "hello"}] = request.messages
    send(provider, {:test_stream_response, {:ok, response}})
    Task.await(next)
  end

  test "legacy sessions keep the original gate" do
    blocking =
      start_supervised!(
        {Session,
         instructions: "Be concise",
         history_mode: :host_settled,
         model_provider: Vxpipe.AgentRuntime.TestModelProvider,
         model: %{mode: :block, test_owner: self()},
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
         event_destination: self()},
        id: :legacy_blocking_session
      )

    first =
      Task.async(fn -> Session.request(blocking, "first", %{request_id: "legacy-busy-a"}) end)

    assert_receive {:model_provider_process, first_provider, request}
    assert List.last(request.messages).content == "first"
    # Ordinary second request while worker runs is busy (original gate, no overlap).
    assert {:error, :busy} = Session.request(blocking, "second", %{request_id: "legacy-busy-b"})
    send(first_provider, :release)
    assert {:ok, %Result{}} = Task.await(first)
  end

  test "settlement while a worker runs does not clobber history and orders receipt before B input" do
    session = start_host_settled_session()

    first = Task.async(fn -> Session.request(session, "first", %{request_id: "clobber-a"}) end)
    assert_receive {:model_stream_process, first_provider, _request}

    send(
      first_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: speaker("first answer")), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(first)

    second =
      Task.async(fn ->
        Session.continue_tool_result(session, "tool finished", %{request_id: "clobber-b"}, 5_000)
      end)

    assert_receive {:model_stream_process, second_provider, overlap_request}
    # B's worker admitted while A outstanding; B's input already in history.
    contents = Enum.map(overlap_request.messages, & &1.content)
    assert Enum.any?(contents, &String.contains?(&1, "first"))

    assert {:ok, spoken} = Message.spoken_assistant("agent", "first answer", :speaker, 4_096)
    assert :ok = Session.settle_output(session, %{request_id: "clobber-a"}, spoken)

    send(
      second_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: listener()), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(second)
    assert :ok = Session.settle_output(session, %{request_id: "clobber-b"}, nil)

    # A settled message must survive B's worker commit and appear before B's input.
    third_task =
      Task.async(fn -> Session.request(session, "third", %{request_id: "clobber-c"}) end)

    assert_receive {:model_stream_process, third_provider, third_request}

    send(
      third_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: listener()), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(third_task)

    contents = Enum.map(third_request.messages, & &1.content)
    assert Enum.any?(contents, &String.contains?(&1, "first answer"))
    assert Enum.any?(contents, &String.contains?(&1, "tool finished"))
    assert Enum.any?(contents, &String.contains?(&1, "third"))

    first_idx = Enum.find_index(contents, &String.contains?(&1, "first answer"))
    tool_idx = Enum.find_index(contents, &String.contains?(&1, "tool finished"))
    assert first_idx < tool_idx
  end

  test "premature receipt for active worker is stale without dropping replay" do
    session = start_host_settled_session()

    first = Task.async(fn -> Session.request(session, "first", %{request_id: "premature-a"}) end)
    assert_receive {:model_stream_process, first_provider, first_request}
    # Premature receipt for the running worker's own correlation is stale.
    assert {:error, :stale_settlement} =
             Session.settle_output(session, %{request_id: "premature-a"}, nil)

    # Worker can still complete and its replay must be retained.
    send(
      first_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: speaker("first answer")), 1)}}
    )

    assert {:ok, %Result{status: :completed}} = Task.await(first)
    assert {:ok, spoken} = Message.spoken_assistant("agent", "first answer", :speaker, 4_096)
    assert :ok = Session.settle_output(session, %{request_id: "premature-a"}, spoken)
    assert Enum.any?(first_request.messages, &(&1.content == "first"))
  end

  test "bounded outstanding, stale settlements and correlation reuse" do
    session = start_host_settled_session()

    first = Task.async(fn -> Session.request(session, "first", %{request_id: "bound-a"}) end)
    assert_receive {:model_stream_process, first_provider, _}

    send(
      first_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: speaker("answer a")), 1)}}
    )

    assert {:ok, %Result{}} = Task.await(first)

    second_task =
      Task.async(fn ->
        Session.continue_tool_result(session, "tool done", %{request_id: "bound-b"}, 5_000)
      end)

    assert_receive {:model_stream_process, second_provider, _}
    # Reusing A's correlation while outstanding must not overwrite its replay.
    assert {:error, :busy} =
             Session.continue_tool_result(session, "tool again", %{request_id: "bound-a"}, 100)

    # Third outstanding must be refused at capacity (A + B).
    assert {:error, :busy} = Session.request(session, "third", %{request_id: "bound-c"})

    send(
      second_provider,
      {:test_stream_response,
       {:ok, elem(Vxpipe.AgentRuntime.ModelResponse.new(text: listener()), 1)}}
    )

    assert {:ok, %Result{}} = Task.await(second_task)

    assert {:ok, spoken} = Message.spoken_assistant("agent", "answer a", :speaker, 4_096)
    assert :ok = Session.settle_output(session, %{request_id: "bound-a"}, spoken)
    # Duplicate settle is stale and must not append again.
    assert {:error, :stale_settlement} =
             Session.settle_output(session, %{request_id: "bound-a"}, spoken)

    assert {:error, :stale_settlement} =
             Session.settle_output(session, %{request_id: "unknown"}, nil)
  end

  defp start_host_settled_session do
    start_supervised!(
      {Session,
       instructions: "Be concise",
       history_mode: :host_settled,
       reply_protocol: :mode_message_v1,
       model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
       model: %{test_owner: self()},
       pending_context_source:
         {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
       event_destination: self()}
    )
  end
end
