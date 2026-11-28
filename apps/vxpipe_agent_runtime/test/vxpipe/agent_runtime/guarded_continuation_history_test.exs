defmodule Vxpipe.AgentRuntime.GuardedContinuationHistoryTest do
  use ExUnit.Case, async: true

  @behaviour Vxpipe.AgentRuntime.RoundAdmission
  alias Vxpipe.AgentRuntime.{
    CompactionResult,
    ModelResponse,
    Result,
    Session,
    ToolCall,
    ToolDescriptor
  }

  @feedback "Use the published support policy."
  @rejected_input "The caller's rejected input marker."
  @rejected_draft "The assistant's denied draft marker."
  @rejected_tool "rejected_tool_marker"
  @partial "Unreleased rewrite marker."

  test "cancelling a semantic rewrite preserves the earlier ordinary tool exchange exactly once" do
    session = session()
    correlation = %{request_id: "with-tool"}
    task = Task.async(fn -> Session.request(session, "Look up this case.", correlation) end)
    {model, _} = next_model()

    accepted = call("case-lookup")
    respond(model, "", [accepted])
    verdict({:accept})
    assert_receive {:tool_submitted, _, :lookup, %{}, ^correlation, "case-lookup"}

    {model, continuation} = next_model()
    assert_exchange(continuation, accepted)
    send(model, {:test_stream_delta, @rejected_draft})
    respond(model, @rejected_draft, [call(@rejected_tool)])
    verdict({:repair, %{messages: [@feedback]}})

    # The real compactor runs while this rewrite's private model request is staged.
    compact_without_private_input()
    assert_receive {:model_stream_process, rewrite, request}
    assert request.tools == []
    assert List.last(request.messages).content =~ @feedback
    assert_exchange(request, accepted)
    refute_contains(request, [@rejected_draft, @rejected_tool])

    # The provider acknowledges this fragment, but admission never saw a final rewrite.
    worker = Process.monitor(rewrite)
    send(rewrite, {:test_stream_delta, @partial, self()})
    assert_receive {:test_stream_delta_result, ^rewrite, :ok}
    assert :ok = Session.cancel(session)
    assert {:ok, %Result{status: :cancelled}} = Task.await(task)
    assert_receive {:DOWN, ^worker, :process, ^rewrite, _}
    refute_received {:agent_runtime_event, %{kind: :text_delta}}

    next =
      Task.async(fn -> Session.request(session, "What happened?", %{request_id: "later"}) end)

    {model, following} = next_model()
    assert_exchange(following, accepted)
    refute_contains(following, [@rejected_draft, @rejected_tool, @feedback, @partial])
    refute_received {:tool_submitted, _, _, _, _, _}
    respond(model, "The lookup was submitted.")
    verdict({:accept})
    assert {:ok, %Result{status: :completed}} = Task.await(next)
  end

  test "a rejected caller's input and authored feedback never enter the compactor" do
    session = session()

    task =
      Task.async(fn ->
        Session.request_guarded(
          session,
          :private,
          {:feedback, @feedback, @rejected_input, nil},
          %{request_id: "blocked"},
          fn -> true end,
          2_000
        )
      end)

    compact_without_private_input()
    assert_receive {:model_stream_process, model, request}
    assert request.tools == []
    assert List.last(request.messages).content == @feedback
    refute_contains(request, [@rejected_input])
    respond(model, "Let me explain the policy.")
    verdict({:accept})
    assert {:ok, %Result{status: :completed}} = Task.await(task)

    next =
      Task.async(fn ->
        Session.request(session, "Next allowed input.", %{request_id: "later"})
      end)

    compact_without_private_input()
    assert_receive {:model_stream_process, model, following}
    refute_contains(following, [@rejected_input, @feedback])
    respond(model, "Happy to help.")
    verdict({:accept})
    assert {:ok, %Result{status: :completed}} = Task.await(next)
  end

  @impl true
  def admit(candidate, _context, observer) do
    send(observer, {:proposed, self(), candidate})

    receive do
      {:verdict, verdict} -> verdict
    end
  end

  defp verdict(value) do
    assert_receive {:proposed, worker, _}
    send(worker, {:verdict, value})
  end

  defp session do
    {:ok, descriptor} =
      ToolDescriptor.new(
        name: "lookup",
        description: "Look up one case",
        input_schema: %{"type" => "object", "properties" => %{}},
        binding: %{test_owner: self(), identity: :lookup, submission: {:accepted, :non_blocking}}
      )

    session =
      start_supervised!(
        {Session,
         instructions: "Provide support.",
         tools: [descriptor],
         executor: Vxpipe.AgentRuntime.TestExecutor,
         model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
         model: %{test_owner: self()},
         round_admission: {__MODULE__, self()},
         event_destination: self(),
         pending_context_source:
           {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: {:ok, []}}},
         context_compaction: [
           enabled: true,
           context_window_tokens: 1_000,
           output_reserve_tokens: 200,
           recent_entries: 1,
           input_token_counter:
             {Vxpipe.AgentRuntime.TestInputTokenCounter, %{owner: self(), result: :manual}},
           compactor:
             {Vxpipe.AgentRuntime.TestContextCompactor, %{owner: self(), result: :manual}}
         ]}
      )

    for n <- 1..3,
        do:
          assert(
            :ok =
              Session.record_assistant(session, "Public history #{n}.", %{
                request_id: "public-#{n}"
              })
          )

    session
  end

  defp next_model do
    count(300)
    assert_receive {:model_stream_process, model, request}
    {model, request}
  end

  defp compact_without_private_input do
    count(700)
    count(300)
    assert_receive {:context_compaction_requested, compactor, request}
    assert request.messages != []

    refute_contains(request, [
      @rejected_input,
      @rejected_draft,
      @rejected_tool,
      @feedback,
      @partial
    ])

    {:ok, summary} = CompactionResult.new(summary: "Public support history.")
    send(compactor, {:context_compaction_result, {:ok, summary}})
    count(300)
  end

  defp count(n) do
    assert_receive {:input_tokens_counted, counter, _}
    send(counter, {:input_token_count, n})
  end

  defp assert_exchange(request, call) do
    assert Enum.flat_map(request.messages, & &1.tool_calls) == [call]

    assert [%{tool_call_id: id, content: content}] =
             Enum.filter(request.messages, &(&1.role == :tool))

    assert id == call.id
    assert JSON.decode!(content) == %{"invocation_id" => id, "status" => "running"}
  end

  defp refute_contains(term, fragments) do
    # Inspect intentionally redacts some of these structs. Compare the entire actual term.
    bytes = :erlang.term_to_binary(term)
    for text <- fragments, do: assert(:binary.match(bytes, text) == :nomatch)
  end

  defp call(id) do
    {:ok, tool} = ToolCall.new(id: id, name: "lookup", arguments: %{})
    tool
  end

  defp respond(worker, text, calls \\ []) do
    send(worker, {:test_stream_response, ModelResponse.new(text: text, tool_calls: calls)})
  end
end
