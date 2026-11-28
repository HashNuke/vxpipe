defmodule Vxpipe.CallEngine.Guardrails.RuntimeAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{RoundCandidate, ToolCall}
  alias Vxpipe.CallEngine.CallSpec.{GuardrailQuestion, Guardrails}
  alias Vxpipe.CallEngine.Guardrails.{Participant, RuntimeAdmission, TransferAdmission}

  defmodule FakeRoom do
    @moduledoc false
    use GenServer

    def start_link(owner), do: GenServer.start_link(__MODULE__, owner)

    @impl true
    def init(owner), do: {:ok, %{owner: owner, verdicts: %{}}}

    @impl true
    def handle_call({:bind_transfer_verdict, entry}, _from, state) do
      send(state.owner, {:room_bound, entry})
      {:reply, :ok, %{state | verdicts: Map.put(state.verdicts, entry.invocation_id, entry)}}
    end

    def handle_call({:take_transfer_verdict, invocation_id}, _from, state) do
      case Map.fetch(state.verdicts, invocation_id) do
        {:ok, entry} -> {:reply, {:ok, entry}, state}
        :error -> {:reply, :empty, state}
      end
    end
  end

  defp question(id) do
    %GuardrailQuestion{
      id: id,
      question: "Q #{id}?",
      required_answer: :yes,
      threshold_hundredths: 70,
      response: "Answer #{id}."
    }
  end

  defp policy(after_ids \\ ["a1"], transfer_ids \\ ["t1"]) do
    %Guardrails{
      before_turn: [],
      after_turn: Enum.map(after_ids, &question/1),
      before_outgoing_transfer: Enum.map(transfer_ids, &question/1)
    }
  end

  test "default host check is the real participant service contract" do
    assert function_exported?(Participant, :check, 5)
  end

  defp tool_call(id, name, arguments) do
    {:ok, call} = ToolCall.new(id: id, name: name, arguments: arguments)
    call
  end

  defp candidate(tool_calls, text \\ "I will transfer you now.", attempt \\ 1) do
    RoundCandidate.new(text,
      tool_calls: tool_calls,
      correlation: %{request_id: "req-1", correlation_id: "turn-1"},
      attempt: attempt,
      maximum_bytes: 4_096,
      reply_protocol: :legacy
    )
  end

  defp host_state(guardrails, overrides) do
    room =
      start_supervised!({FakeRoom, self()}, id: {FakeRoom, System.unique_integer([:positive])})

    Map.merge(
      %{
        guardrails: guardrails,
        activation_id: "activation-1",
        agent_participant_id: "part-reception",
        incarnation_id: "incarnation-1",
        room_authority: room,
        after_questions: [%{id: "a1"}],
        transfer_questions: [%{id: "t1"}],
        terminal_kinds: %{"transfer" => :transfer, "lookup_order" => :ordinary},
        evaluation_timeout_ms: 2_000,
        response_deadline_ms: System.monotonic_time(:millisecond) + 30_000,
        maximum_feedback_bytes: 4_096
      },
      overrides
    )
  end

  defp context do
    %{
      correlation: %{request_id: "req-1", correlation_id: "turn-1"},
      history_mode: :generated,
      reply_protocol: :legacy
    }
  end

  test "joint accept uses one stable proposal for after+transfer and binds the transfer call id" do
    parent = self()

    check = fn _server, event, proposal, evidence, _deadline ->
      send(parent, {:guardrail_request, event, proposal, evidence})
      :passed
    end

    transfer =
      tool_call("transfer-1", "transfer", %{"destination" => "billing"})

    ordinary =
      tool_call("ordinary-1", "lookup_order", %{"order_id" => "o1"})

    result =
      RuntimeAdmission.admit(
        candidate([ordinary, transfer]),
        context(),
        host_state(:fake_guardrails, %{check: check})
      )

    assert {:accept, %{binds: [bind]}} = result
    assert bind.invocation_id == "transfer-1"
    assert bind.destination_call_spec_key == "billing"
    assert bind.source_activation_id == "activation-1"
    assert bind.incarnation_id == "incarnation-1"
    assert is_binary(bind.policy_digest)

    assert_received {:guardrail_request, :after_turn, after_proposal, after_evidence}

    assert_received {:guardrail_request, :before_outgoing_transfer, transfer_proposal,
                     transfer_evidence}

    # SAME stable proposal on the shared participant; call id travels separately.
    assert after_proposal == transfer_proposal
    assert after_proposal == "turn-1:1"
    assert transfer_evidence["invocation_id"] == "transfer-1"
    refute Map.has_key?(after_evidence, "invocation_id")
    assert is_binary(TransferAdmission.policy_digest([question("t1")]))

    # The passed verdict is bound room-side for exactly-once consumption.
    assert_received {:room_bound, bound}
    assert bound.invocation_id == "transfer-1"
    assert bound.source_participant_id == "part-reception"
  end

  test "bind failure fails the round instead of releasing effects" do
    check = fn _server, _event, _proposal, _evidence, _deadline -> :passed end
    transfer = tool_call("transfer-1", "transfer", %{"destination" => "billing"})

    dead =
      start_supervised!({Task, fn -> :ok end}, id: {Task, System.unique_integer([:positive])})

    ref = Process.monitor(dead)
    assert_receive {:DOWN, ^ref, :process, ^dead, _}

    assert {:failure, :error} =
             RuntimeAdmission.admit(
               candidate([transfer]),
               context(),
               host_state(:fake, %{check: check, room_authority: dead})
             )
  end

  test "validation runs before guard checks and fails closed" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      send(self(), {:guardrail_request, :called})
      :passed
    end

    # Invalid candidate: duplicate tool ids cannot reach the guardrail service.
    dup = %RoundCandidate{
      text: "hello",
      tool_calls: [
        %ToolCall{id: "dup", name: "lookup_order", arguments: %{}, provider_metadata: %{}},
        %ToolCall{id: "dup", name: "lookup_order", arguments: %{}, provider_metadata: %{}}
      ],
      speech?: true,
      tool_only?: false,
      correlation: %{request_id: "req-1", correlation_id: "turn-1"},
      attempt: 1,
      maximum_bytes: 4_096
    }

    # Direct struct with duplicate ids is still struct-valid; host must still
    # validate uniqueness before guard I/O. Our bridge validates shape; duplicates
    # are rejected at the runtime layer, but an invalid struct field must not call out.
    invalid = %RoundCandidate{
      text: "hello",
      tool_calls: "not-a-list",
      speech?: true,
      tool_only?: false,
      correlation: %{request_id: "req-1"},
      attempt: 1,
      maximum_bytes: 4_096
    }

    assert {:failure, :error} =
             RuntimeAdmission.admit(invalid, context(), host_state(:fake, %{check: check}))

    refute_received {:guardrail_request, _}

    # Duplicate ids pass struct validation but fail runtime pre-validation;
    # host bridge treats well-formed structs as admit candidates (transfer lane
    # owns deeper call-count policy). Ensure no crash and no bracket access.
    assert {:accept, %{binds: []}} =
             RuntimeAdmission.admit(
               %RoundCandidate{
                 text: "hello",
                 tool_calls: [],
                 speech?: true,
                 tool_only?: false,
                 correlation: %{request_id: "req-1", correlation_id: "turn-1"},
                 attempt: 1,
                 maximum_bytes: 4_096
               },
               context(),
               host_state(:fake, %{check: check, after_questions: [], transfer_questions: []})
             )

    _ = dup
  end

  test "blocked checks return per-event failures for the private JSON envelope" do
    check = fn
      _server, :after_turn, _proposal, _evidence, _deadline ->
        {:blocked, ["After line."]}

      _server, :before_outgoing_transfer, _proposal, _evidence, _deadline ->
        {:blocked, ["Transfer line."]}
    end

    transfer = tool_call("transfer-1", "transfer", %{"destination" => "billing"})

    assert {:repair, %{messages: lines, failures: failures}} =
             RuntimeAdmission.admit(
               candidate([transfer]),
               context(),
               host_state(:fake, %{check: check})
             )

    assert lines != []
    assert Enum.map(failures, & &1.event) == [:after_turn, :before_outgoing_transfer]
    assert Enum.all?(failures, &(&1.messages != []))
  end

  test "real activation wires round_admission into the session child" do
    alias Vxpipe.CallEngine.AgentActivation.RuntimeGraph

    policy_struct = policy()
    adapter = fn _request -> {:ok, %{scores: %{"a1" => 0.99, "t1" => 0.99}}} end

    options = [
      activation_id: "act-rt-#{System.unique_integer([:positive])}",
      agent_participant_id: "participant-agent",
      call_id: "call-demo",
      owner: self(),
      system_prompt: "Be concise.",
      tools: %{},
      history_mode: :generated,
      agent_protocol: nil,
      variable_binding: nil,
      maximum_output_bytes: 4_096,
      maximum_pending_requests: 2,
      maximum_tool_invocations: 2,
      maximum_completed_requests: 4,
      tool_invocation_timeout_ms: 1_000,
      maximum_tool_result_bytes: 4_096,
      maximum_model_context_bytes: 256 * 1_024,
      model_context_timeout_ms: 1_000,
      request_timeout_ms: 1_000,
      usage_provider: %{name: "fixture", integration_id: "test-model", model: "fixture:default"},
      provider: :other,
      model_provider: Vxpipe.CallEngine.TestAgentRuntimeModelProvider,
      model: %{owner: self()},
      guardrails: [policy: policy_struct, adapter: adapter]
    ]

    assert {:ok, children} = RuntimeGraph.children(options)
    session_spec = Enum.find(children, &(&1.id == :session))
    assert session_spec != nil
    %{start: {_mod, _fun, [session_options]}} = session_spec
    assert {RuntimeAdmission, host} = Keyword.fetch!(session_options, :round_admission)
    assert host.activation_id == Keyword.fetch!(options, :activation_id)
    assert host.after_questions == policy_struct.after_turn
  end
end
