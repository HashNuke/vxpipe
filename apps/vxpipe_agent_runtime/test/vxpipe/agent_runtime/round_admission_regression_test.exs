defmodule Vxpipe.AgentRuntime.RoundAdmissionRegressionTest do
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

  test "oversized private input feedback ends before submitting the model request" do
    session = start_session([], maximum_model_context_bytes: 100)

    feedback =
      JSON.encode!(%{
        type: "guardrail_failure",
        status: "blocked",
        failures: [%{event: :before_turn, messages: [String.duplicate("a", 100)]}]
      })

    assert {:error, :oversized} =
             Session.request_guarded(
               session,
               :private,
               {:feedback, feedback, "trigger"},
               %{request_id: "input-budget"},
               fn -> true end,
               500
             )

    owner = self()

    assert {:error, :oversized} =
             Session.request_guarded(
               session,
               :private,
               {:feedback, feedback, "trigger", fn -> send(owner, :feedback_dispatched) end},
               %{request_id: "input-budget"},
               fn -> true end,
               500
             )

    refute_received :feedback_dispatched

    refute_received {:pending_context_requested, _, _, _}
    refute_received {:model_provider_process, _, _}
  end

  for provider <- [
        Vxpipe.AgentRuntime.TestModelProvider,
        Vxpipe.AgentRuntime.TestStreamingModelProvider
      ] do
    @provider provider
    test "an immediate failure from #{inspect(provider)} does not confirm private feedback" do
      session = start_session([], model_provider: @provider)
      task = private_request(session, "undispatched")

      message =
        if @provider == Vxpipe.AgentRuntime.TestModelProvider,
          do: :model_provider_process,
          else: :model_stream_process

      assert_receive {^message, worker, %{tools: []}}
      refute_received :dispatch_confirmed

      kind =
        if @provider == Vxpipe.AgentRuntime.TestModelProvider,
          do: :test_model_response,
          else: :test_stream_response

      send(worker, {kind, {:error, :transport_error}})
      assert {:ok, %Result{status: :failed}} = Task.await(task)
      refute_received :dispatch_confirmed
    end
  end

  test "a provider exception before producing evidence cannot confirm feedback" do
    # The fixture's synchronous provider fetches its configured reply and raises if absent.
    session = start_session([], model: %{mode: :reply, test_owner: self()})
    task = private_request(session, "provider-raises")
    assert_receive {:model_provider_process, _, _}
    assert {:ok, %Result{status: :failed, reason: :provider_unavailable}} = Task.await(task)
    refute_received :dispatch_confirmed
  end

  test "a streaming provider returning a valid response without deltas confirms feedback once" do
    session = start_session([], model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider)
    task = private_request(session, "final-receipt")
    assert_receive {:model_stream_process, worker, request}
    assert List.last(request.messages).content == "private guardrail feedback"
    refute_received :dispatch_confirmed
    send(worker, {:test_stream_response, ModelResponse.new(text: "Hello")})
    assert {:ok, %Result{status: :completed}} = Task.await(task)
    assert_receive :dispatch_confirmed
    refute_received :dispatch_confirmed
  end

  test "the first provider stream event confirms feedback once while proposed speech stays private" do
    session =
      start_session([],
        model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = private_request(session, "stream-receipt")
    assert_receive {:model_stream_process, worker, request}
    assert List.last(request.messages).content == "private guardrail feedback"
    refute_received :dispatch_confirmed
    send(worker, {:test_stream_delta, "d"})
    assert_receive :dispatch_confirmed
    send(worker, {:test_stream_delta, "raft"})
    send(worker, {:test_stream_response, ModelResponse.new(text: "draft")})
    assert_receive {:round_admission_requested, _, _, admission}
    refute_received {:agent_runtime_event, %{kind: :text_delta}}
    send(admission, {:admission_verdict, {:failure, :blocked}})
    assert {:ok, %Result{status: :failed}} = Task.await(task)
    refute_received :dispatch_confirmed
    refute_received {:agent_runtime_event, %{kind: :text_delta}}
  end

  test "tool continuation retries after withheld partial output and releases only the second stream" do
    session =
      start_session([],
        model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task =
      Task.async(fn ->
        Session.continue_tool_result(session, "result", %{request_id: "guarded-retry"}, 2_000)
      end)

    release_pending_context("guarded-retry", [])
    assert_receive {:model_stream_process, first, _}
    send(first, {:test_stream_delta, "withheld failed attempt"})
    send(first, {:test_stream_response, {:error, :transport_error}})
    assert_receive {:model_stream_process, retry, _}, 1_000
    send(retry, {:test_stream_delta, "safe "})
    send(retry, {:test_stream_delta, "replacement"})
    send(retry, {:test_stream_response, ModelResponse.new(text: "safe replacement")})
    assert_receive {:round_admission_requested, _, _, admission}
    refute_received {:agent_runtime_event, %{kind: :text_delta}}
    send(admission, {:admission_verdict, {:accept}})
    assert {:ok, %Result{status: :completed, output: "safe replacement"}} = Task.await(task)
    assert_receive {:agent_runtime_event, %{kind: :text_delta, data: %{text: "safe "}}}
    assert_receive {:agent_runtime_event, %{kind: :text_delta, data: %{text: "replacement"}}}
    refute_received {:agent_runtime_event, %{kind: :text_delta}}
    refute_received {:tool_submitted, _, _, _, _, _}
  end

  defp private_request(session, id) do
    owner = self()

    task =
      Task.async(fn ->
        Session.request_guarded(
          session,
          :private,
          {:feedback, "private guardrail feedback", "private blocked caller",
           fn -> send(owner, :dispatch_confirmed) end},
          %{request_id: id},
          fn -> true end,
          2_000
        )
      end)

    release_pending_context(id, [])
    task
  end

  test "repair carries the exact private JSON envelope, never flat text" do
    session =
      start_session(
        [],
        round_admission: {__MODULE__.EnvelopeAdmission, %{owner: self()}}
      )

    task = request(session, "Hello", "envelope_repair")
    release_pending_context("envelope_repair", [])

    assert_receive {:model_provider_process, provider, _}, 1_000
    {:ok, draft} = ModelResponse.new(text: "rejected draft")
    send(provider, {:test_model_response, {:ok, draft}})

    assert_receive {:round_admission_requested, _candidate, _context, admission_pid}, 1_000

    send(
      admission_pid,
      {:admission_verdict,
       {:repair,
        %{
          messages: ["Ask which department."],
          failures: [%{event: :after_turn, messages: ["Ask which department."]}]
        }}}
    )

    release_pending_context("envelope_repair", [])
    assert_receive {:model_provider_process, _provider2, retry_request}, 1_000

    [repair_message] =
      Enum.filter(retry_request.messages, &(&1.role == :user and &1.origin == :engine))

    decoded = JSON.decode!(repair_message.content)
    assert decoded["type"] == "guardrail_failure"
    assert decoded["status"] == "blocked"

    assert decoded["failures"] == [
             %{"event" => "after_turn", "messages" => ["Ask which department."]}
           ]

    refute repair_message.content =~ "Private guardrail repair"

    _ = task
  end

  test "repaired round suppresses tools and rejects a disobedient provider tool" do
    session =
      start_session(
        [descriptor!("check_balance", :balance, {:accepted, :blocking})],
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = request(session, "Check", "disobedient_tool")
    release_pending_context("disobedient_tool", [])

    assert_receive {:model_provider_process, provider, _}, 1_000
    {:ok, draft} = ModelResponse.new(text: "draft")
    send(provider, {:test_model_response, {:ok, draft}})

    assert_receive {:round_admission_requested, _candidate, _context, admission_pid}, 1_000
    send(admission_pid, {:admission_verdict, {:repair, %{messages: ["Try again."]}}})

    release_pending_context("disobedient_tool", [])
    assert_receive {:model_provider_process, provider2, retry_request}, 1_000

    # Repair retry is tool-free.
    assert retry_request.tools == []

    # Disobedient provider still returns a tool: host may even accept, but the
    # runtime rejects without submit/commit/delta effects.
    {:ok, disobedient} =
      ModelResponse.new(text: "still tool", tool_calls: [tool_call("d1", "check_balance")])

    send(provider2, {:test_model_response, {:ok, disobedient}})

    assert_receive {:round_admission_requested, _candidate2, _context2, admission_pid2}, 1_000
    send(admission_pid2, {:admission_verdict, {:accept}})

    assert {:ok, %Result{status: :failed, reason: :guardrail_blocked}} =
             Task.await(task, 2_000)

    refute_received {:tool_submitted, _, _, _, _, _}
  end

  test "only final admitted speech is released; mismatched streamed deltas never flush" do
    session =
      start_session(
        [],
        model_provider: Vxpipe.AgentRuntime.TestStreamingModelProvider,
        round_admission: {__MODULE__.ControllableAdmission, %{owner: self()}}
      )

    task = request(session, "Hello", "mismatch_stream")
    release_pending_context("mismatch_stream", [])
    assert_receive {:model_stream_process, provider, _}, 1_000

    # First attempt streams mismatched deltas, then gets repaired.
    send(provider, {:test_stream_delta, "bad-bad-bad"})
    {:ok, draft} = ModelResponse.new(text: "bad draft")
    send(provider, {:test_stream_response, {:ok, draft}})

    assert_receive {:round_admission_requested, _candidate, _context, admission_pid}, 1_000
    send(admission_pid, {:admission_verdict, {:repair, %{messages: ["Try again."]}}})

    release_pending_context("mismatch_stream", [])
    assert_receive {:model_stream_process, provider2, _}, 1_000

    send(provider2, {:test_stream_delta, "good"})
    {:ok, accepted} = ModelResponse.new(text: "good")
    send(provider2, {:test_stream_response, {:ok, accepted}})

    assert_receive {:round_admission_requested, _candidate2, _context2, admission_pid2}, 1_000
    send(admission_pid2, {:admission_verdict, {:accept}})

    assert {:ok, %Result{status: :completed, output: "good"}} = Task.await(task, 2_000)

    # Rejected deltas never leak; only final admitted speech deltas emit.
    refute_received {:agent_runtime_event, %{kind: :text_delta, data: %{text: "bad-bad-bad"}}}
    assert_received {:agent_runtime_event, %{kind: :text_delta, data: %{text: "good"}}}
  end

  test "host accept with binds is admitted and validation runs before guard checks" do
    session =
      start_session(
        [],
        round_admission: {__MODULE__.BindsAdmission, %{}}
      )

    task = request(session, "Hello", "binds_accept")
    release_pending_context("binds_accept", [])

    assert_receive {:model_provider_process, provider, _}, 1_000
    {:ok, response} = ModelResponse.new(text: "hello")
    send(provider, {:test_model_response, {:ok, response}})

    assert {:ok, %Result{status: :completed, output: "hello"}} = Task.await(task, 2_000)
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

  defmodule EnvelopeAdmission do
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

  defmodule BindsAdmission do
    @behaviour RoundAdmission

    @impl true
    def admit(%RoundCandidate{}, _context, _state) do
      {:accept,
       %{
         binds: [
           %{
             invocation_id: "transfer-1",
             verdict: :passed,
             source_activation_id: "activation-1",
             destination_call_spec_key: "billing",
             policy_digest: nil,
             incarnation_id: "incarnation-1",
             checked_at_ms: 0,
             source: :bound
           }
         ]
       }}
    end
  end

  defp start_session(tools, options) do
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

  defp descriptor!(name, identity, submission) do
    {:ok, descriptor} = descriptor(name, identity, submission)
    descriptor
  end

  defp descriptor(name, identity, submission) do
    ToolDescriptor.new(
      name: name,
      description: "Check",
      input_schema: %{
        "type" => "object",
        "properties" => %{"account_id" => %{"type" => "string"}},
        "required" => ["account_id"],
        "additionalProperties" => false
      },
      binding: %{test_owner: self(), identity: identity, submission: submission}
    )
  end

  defp tool_call(id, name) do
    {:ok, call} =
      ToolCall.new(id: id, name: name, arguments: %{"account_id" => "account_1"})

    call
  end
end
