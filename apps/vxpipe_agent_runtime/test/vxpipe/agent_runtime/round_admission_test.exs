defmodule Vxpipe.AgentRuntime.RoundAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{
    ModelResponse,
    Result,
    RoundAdmission,
    RoundCandidate,
    Session,
    ToolCall,
    ToolDescriptor
  }

  test "terminal descriptor flag defaults to false and accepts explicit true" do
    {:ok, ordinary} = descriptor("check_balance", :balance, {:accepted, :blocking})
    {:ok, terminal} = descriptor("transfer", :transfer, {:accepted, :blocking}, true)

    assert ordinary.terminal? == false
    assert terminal.terminal? == true
  end

  test "round candidate marks tool-only rounds without speech" do
    call = %ToolCall{id: "t1", name: "check_balance", arguments: %{}, provider_metadata: %{}}

    candidate =
      RoundCandidate.new("",
        tool_calls: [call],
        correlation: %{request_id: "r1"},
        attempt: 1,
        maximum_bytes: 512
      )

    assert candidate.tool_only? == true
    assert candidate.speech? == false
  end

  test "mixed text and tools are withheld until host accepts, then released in order" do
    session =
      start_session(
        [descriptor!("check_balance", :balance, {:accepted, :blocking})],
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = request(session, "Check", "admit_mixed")
    release_pending_context("admit_mixed", [])

    assert_receive {:model_provider_process, provider, first_request}, 1_000

    {:ok, response} =
      ModelResponse.new(text: "rejected draft", tool_calls: [tool_call("t1", "check_balance")])

    send(provider, {:test_model_response, {:ok, response}})

    assert_receive {:round_admission_requested, candidate, context, admission_pid}, 1_000
    assert candidate.text == "rejected draft"
    assert Enum.map(candidate.tool_calls, & &1.id) == ["t1"]
    assert candidate.tool_only? == false
    assert candidate.speech? == true
    assert context.correlation == %{request_id: "admit_mixed"}

    # Withheld: no tool invocation before the host verdict.
    refute_received {:tool_submitted, _, _, _, _, _}

    # Repair with private lines; rejected draft must never execute.
    send(admission_pid, {:admission_verdict, {:repair, %{messages: ["Try again."]}}})

    release_pending_context("admit_mixed", [])
    assert_receive {:model_provider_process, provider2, second_request}, 1_000

    # Private repair context rides the retry request only.
    assert Enum.any?(second_request.messages, fn message ->
             message.role == :user and message.content =~ "Try again."
           end)

    refute_received {:tool_submitted, _, _, _, _, _}

    {:ok, accepted} = ModelResponse.new(text: "accepted replacement")
    send(provider2, {:test_model_response, {:ok, accepted}})

    assert_receive {:round_admission_requested, candidate2, _context, admission_pid2}, 1_000
    assert candidate2.text == "accepted replacement"
    assert candidate2.tool_calls == []

    send(admission_pid2, {:admission_verdict, {:accept}})

    assert {:ok, %Result{status: :completed, output: "accepted replacement"}} =
             Task.await(task, 2_000)

    refute_received {:tool_submitted, _, _, _, _, _}
    _ = first_request
  end

  test "terminal tool submits after ordinary tools even when listed first" do
    session =
      start_session([
        descriptor!("check_balance", :ordinary, {:await_release, {:accepted, :blocking}}),
        descriptor!("transfer", :terminal, {:accepted, :blocking}, true)
      ])

    task = request(session, "Move", "terminal_order")
    release_pending_context("terminal_order", [])

    assert_receive {:model_provider_process, provider, _}, 1_000

    {:ok, response} =
      ModelResponse.new(
        text: "moving",
        tool_calls: [tool_call("term-1", "transfer"), tool_call("ord-1", "check_balance")]
      )

    send(provider, {:test_model_response, {:ok, response}})

    # Ordinary must submit first despite model order.
    assert_receive {:tool_submitted, _, :ordinary, _, _, "ord-1"}, 1_000
    refute_received {:tool_submitted, _, :terminal, _, _, "term-1"}

    # Release ordinary worker; terminal may then submit.
    release_blocked_executor()

    assert_receive {:tool_submitted, _, :terminal, _, _, "term-1"}, 1_000
    _ = task
  end

  test "silent tool-only proposal still orders terminal last with default admission" do
    session =
      start_session([
        descriptor!("check_balance", :ordinary, {:await_release, {:accepted, :blocking}}),
        descriptor!("hangup", :terminal, {:accepted, :blocking}, true)
      ])

    task = request(session, "Move", "terminal_silent")
    release_pending_context("terminal_silent", [])

    assert_receive {:model_provider_process, provider, _}, 1_000

    {:ok, response} =
      ModelResponse.new(
        text: "",
        tool_calls: [tool_call("term-9", "hangup"), tool_call("ord-9", "check_balance")]
      )

    send(provider, {:test_model_response, {:ok, response}})

    assert_receive {:tool_submitted, _, :ordinary, _, _, "ord-9"}, 1_000
    refute_received {:tool_submitted, _, :terminal, _, _, "term-9"}

    release_blocked_executor()
    assert_receive {:tool_submitted, _, :terminal, _, _, "term-9"}, 1_000
    _ = task
  end

  test "an ordinary submission rejection withholds its terminal sibling" do
    session =
      start_session([
        descriptor!("lookup", :ordinary, {:error, :rejected}),
        descriptor!("transfer", :terminal, {:accepted, :blocking}, true)
      ])

    task = request(session, "Move", "submit-rejected")
    release_pending_context("submit-rejected", [])
    assert_receive {:model_provider_process, provider, _}

    {:ok, response} =
      ModelResponse.new(
        text: "",
        tool_calls: [
          tool_call("term-rejected", "transfer"),
          tool_call("ord-rejected", "lookup")
        ]
      )

    send(provider, {:test_model_response, {:ok, response}})
    release_pending_context("submit-rejected", [])
    assert_receive {:model_provider_process, continuation, next}
    refute_received {:tool_submitted, _, :terminal, _, _, "term-rejected"}

    assert Enum.any?(next.messages, fn message ->
             message.role == :tool and message.content =~ "ordinary_failed"
           end)

    {:ok, final} = ModelResponse.new(text: "I could not transfer.")
    send(continuation, {:test_model_response, {:ok, final}})
    assert {:ok, %Result{status: :completed}} = Task.await(task)
  end

  test "streamed deltas are buffered until host accept" do
    session =
      start_session(
        [],
        model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = request(session, "Hello", "admit_stream")
    release_pending_context("admit_stream", [])
    assert_receive {:model_stream_process, provider, _}, 1_000

    send(provider, {:test_stream_delta, "hel"})
    send(provider, {:test_stream_delta, "lo"})
    {:ok, response} = ModelResponse.new(text: "hello")
    send(provider, {:test_stream_response, {:ok, response}})

    assert_receive {:round_admission_requested, candidate, _context, admission_pid}, 1_000
    assert candidate.text == "hello"

    # Buffered: no public delta before accept.
    refute_received {:agent_runtime_event, %{kind: :text_delta}}

    send(admission_pid, {:admission_verdict, {:accept}})

    assert_receive {:agent_runtime_event, %{kind: :text_delta, data: %{text: "hel"}}}, 1_000
    assert_receive {:agent_runtime_event, %{kind: :text_delta, data: %{text: "lo"}}}, 1_000

    assert {:ok, %Result{status: :completed, output: "hello"}} = Task.await(task, 2_000)
  end

  test "interruption during pending admission cancels without effects" do
    session =
      start_session(
        [descriptor!("check_balance", :balance, {:accepted, :blocking})],
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = request(session, "Check", "admit_cancel")
    release_pending_context("admit_cancel", [])

    assert_receive {:model_provider_process, provider, _}, 1_000

    {:ok, response} =
      ModelResponse.new(text: "draft", tool_calls: [tool_call("c1", "check_balance")])

    send(provider, {:test_model_response, {:ok, response}})

    assert_receive {:round_admission_requested, _candidate, _context, _pid}, 1_000
    :ok = Session.cancel(session)

    assert {:ok, %Result{status: :cancelled}} = Task.await(task, 2_000)
    refute_received {:tool_submitted, _, _, _, _, _}
  end

  test "admission repair budget exhaustion fails without leaking rejected draft" do
    session =
      start_session(
        [],
        round_admission:
          {__MODULE__.AlwaysRepair, %{messages: ["Failed guardrail: Q Required: Yes."]}},
        maximum_admission_repairs: 1
      )

    task = request(session, "Hello", "admit_exhaust")
    release_pending_context("admit_exhaust", [])

    assert_receive {:model_provider_process, provider1, _}, 1_000
    {:ok, draft1} = ModelResponse.new(text: "draft one")
    send(provider1, {:test_model_response, {:ok, draft1}})

    release_pending_context("admit_exhaust", [])
    assert_receive {:model_provider_process, provider2, second_request}, 1_000

    # Repair context is present on the retry but never committed as history.
    assert Enum.any?(second_request.messages, fn message ->
             message.role == :user and message.content =~ "Failed guardrail"
           end)

    {:ok, draft2} = ModelResponse.new(text: "draft two")
    send(provider2, {:test_model_response, {:ok, draft2}})

    assert {:ok, %Result{status: :failed, reason: :guardrail_blocked}} =
             Task.await(task, 2_000)
  end

  defmodule ControllableAdmission do
    @behaviour RoundAdmission

    @impl true
    def admit(%RoundCandidate{} = candidate, context, %{owner: owner})
        when is_map(context) do
      send(owner, {:round_admission_requested, candidate, context, self()})

      receive do
        {:admission_verdict, verdict} -> verdict
      end
    end
  end

  defmodule AlwaysRepair do
    @behaviour RoundAdmission

    @impl true
    def admit(_candidate, _context, %{messages: messages}), do: {:repair, %{messages: messages}}
  end

  defp start_session(tools, options \\ []) do
    start_supervised!(
      {Session,
       Keyword.merge(
         [
           instructions: "Be concise",
           model_provider: Vxpipe.AgentRuntime.TestModelProvider,
           model: %{mode: :scripted, test_owner: self()},
           tools: tools,
           executor: Vxpipe.AgentRuntime.TestExecutor,
           maximum_model_rounds: 4,
           pending_context_source:
             {Vxpipe.AgentRuntime.TestPendingContextSource, %{owner: self(), result: :block}},
           event_destination: self()
         ],
         options
       )}
    )
  end

  defp request(session, text, request_id) do
    Task.async(fn -> Session.request(session, text, %{request_id: request_id}) end)
  end

  defp release_pending_context(request_id, invocations) do
    assert_receive {:pending_context_requested, source, %{request_id: ^request_id}, 1_000}
    send(source, {:release, {:ok, invocations}})
  end

  defp release_blocked_executor do
    for pid <- Process.list(),
        {:current_function, {Vxpipe.AgentRuntime.TestExecutor, :await_release, 1}} ==
          Process.info(pid, :current_function) do
      send(pid, :release_submission)
    end

    :ok
  end

  defp descriptor!(name, identity, submission, terminal? \\ false) do
    {:ok, descriptor} = descriptor(name, identity, submission, terminal?)
    descriptor
  end

  defp descriptor(name, identity, submission, terminal? \\ false) do
    ToolDescriptor.new(
      name: name,
      description: "Check",
      input_schema: %{
        "type" => "object",
        "properties" => %{"account_id" => %{"type" => "string"}},
        "required" => ["account_id"],
        "additionalProperties" => false
      },
      binding: %{test_owner: self(), identity: identity, submission: submission},
      terminal?: terminal?
    )
  end

  defp tool_call(id, name) do
    {:ok, call} =
      ToolCall.new(id: id, name: name, arguments: %{"account_id" => "account_1"})

    call
  end
end
