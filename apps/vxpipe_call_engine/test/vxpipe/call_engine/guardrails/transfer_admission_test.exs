defmodule Vxpipe.CallEngine.Guardrails.TransferAdmissionTest do
  use ExUnit.Case, async: true

  alias Vxpipe.AgentRuntime.{RoundCandidate, ToolCall}
  alias Vxpipe.CallEngine.Guardrails.TransferAdmission

  defp tool_call(id, name, arguments \\ %{}) do
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

  defp context do
    %{
      tool_registry: Vxpipe.CallEngine.TestGuardrailToolRegistry.new(),
      correlation: %{request_id: "req-1", correlation_id: "turn-1"},
      history_mode: :generated,
      reply_protocol: :legacy
    }
  end

  defp host(overrides) do
    Map.merge(
      %{
        guardrails: :fake_guardrails,
        activation_id: "activation-1",
        incarnation_id: "incarnation-1",
        after_questions: [%{id: "a1"}],
        transfer_questions: [%{id: "t1"}],
        policy_revision: 4,
        terminal_kinds: %{"transfer" => :transfer, "lookup_order" => :ordinary},
        evaluation_timeout_ms: 2_000,
        response_deadline_ms: System.monotonic_time(:millisecond) + 30_000,
        maximum_feedback_bytes: 4_096
      },
      overrides
    )
  end

  @transfer_call_id "transfer-1"

  defp calls do
    [
      tool_call("ordinary-1", "lookup_order", %{"order_id" => "secret-must-not-leak"}),
      tool_call(@transfer_call_id, "transfer", %{"destination" => "billing"})
    ]
  end

  test "guarded duplicate transfers reject the round before checking either event" do
    parent = self()

    check = fn _, event, _, _, _ ->
      send(parent, {:checked, event})
      :passed
    end

    for destination <- ["billing", "support"] do
      duplicate =
        tool_call("second-transfer", "transfer", %{
          "destination" => destination,
          "reason" => "Unreviewed reason"
        })

      candidate = candidate(calls() ++ [duplicate])

      assert {:failure, :error} =
               TransferAdmission.joint_admit(candidate, context(), host(%{check: check}))

      refute_received {:checked, _}

      assert {:accept, %{binds: []}} =
               TransferAdmission.joint_admit(
                 candidate,
                 context(),
                 host(%{check: check, transfer_questions: []})
               )

      assert_received {:checked, :after_turn}
      refute_received {:checked, :before_outgoing_transfer}
    end
  end

  test "joint accept shares one stable proposal and binds the transfer call id" do
    parent = self()

    check = fn _server, event, proposal, _evidence, _deadline ->
      send(parent, {:checked, event, proposal})
      :passed
    end

    assert {:accept, %{binds: [bind]}} =
             TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: check}))

    assert_received {:checked, :after_turn, "turn-1:1"}
    assert_received {:checked, :before_outgoing_transfer, "turn-1:1"}

    assert bind.invocation_id == @transfer_call_id
    assert bind.verdict == :passed
    assert bind.source_activation_id == "activation-1"
    assert bind.destination_call_spec_key == "billing"
    assert bind.incarnation_id == "incarnation-1"
    assert is_binary(bind.policy_digest)
    assert bind.policy_revision == 4
  end

  test "transfer block with after pass returns per-event repair" do
    check = fn
      _server, :after_turn, _proposal, _evidence, _deadline ->
        :passed

      _server, :before_outgoing_transfer, _proposal, _evidence, _deadline ->
        {:blocked, ["Ask which department the caller needs."]}
    end

    assert {:repair, %{messages: messages, failures: failures}} =
             TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: check}))

    assert messages == ["Ask which department the caller needs."]

    assert failures == [
             %{
               event: :before_outgoing_transfer,
               messages: ["Ask which department the caller needs."]
             }
           ]
  end

  test "joint block merges lines in stable event order" do
    check = fn
      _server, :after_turn, _proposal, _evidence, _deadline ->
        Process.sleep(50)
        {:blocked, ["After line."]}

      _server, :before_outgoing_transfer, _proposal, _evidence, _deadline ->
        {:blocked, ["Transfer line."]}
    end

    assert {:repair, %{messages: ["After line.", "Transfer line."], failures: failures}} =
             TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: check}))

    assert failures == [
             %{event: :after_turn, messages: ["After line."]},
             %{event: :before_outgoing_transfer, messages: ["Transfer line."]}
           ]
  end

  test "checker error in either check fails the round even when the other blocks" do
    check = fn
      _server, :after_turn, _proposal, _evidence, _deadline ->
        {:blocked, ["After line."]}

      _server, :before_outgoing_transfer, _proposal, _evidence, _deadline ->
        {:error, :unavailable}
    end

    assert {:failure, :error} =
             TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: check}))
  end

  test "cancelled and stale verdicts fence to their own failures" do
    for reason <- [:cancelled, :stale] do
      check = fn _server, _event, _proposal, _evidence, _deadline -> {:error, reason} end

      assert {:failure, ^reason} =
               TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: check}))
    end
  end

  test "oversized current evidence fences to oversized without guardrail I/O" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      flunk("no check must run for oversized evidence")
    end

    big = candidate(calls(), String.duplicate("z", 9 * 1_024))

    assert {:failure, :oversized} =
             TransferAdmission.joint_admit(big, context(), host(%{check: check}))
  end

  test "tool-only transfer round runs only the transfer check" do
    parent = self()

    check = fn _server, event, proposal, _evidence, _deadline ->
      send(parent, {:checked, event, proposal})
      :passed
    end

    tool_only =
      RoundCandidate.new(" ",
        tool_calls: [tool_call(@transfer_call_id, "transfer", %{"destination" => "billing"})],
        correlation: %{request_id: "req-1", correlation_id: "turn-1"},
        attempt: 2,
        maximum_bytes: 4_096,
        reply_protocol: :legacy
      )

    assert {:accept, %{binds: [bind]}} =
             TransferAdmission.joint_admit(tool_only, context(), host(%{check: check}))

    assert_received {:checked, :before_outgoing_transfer, "turn-1:2"}
    refute_received {:checked, :after_turn, _}
    assert bind.invocation_id == @transfer_call_id
  end

  test "joint checks reject a large ordinary proposal before either checker receives evidence" do
    parent = self()

    check = fn _, event, _, _, _ ->
      send(parent, {:checked_oversized, event})
      :passed
    end

    ordinary = tool_call("ordinary", "lookup_order", %{"order_id" => String.duplicate("a", 8192)})
    transfer = tool_call(@transfer_call_id, "transfer", %{"destination" => "billing"})

    assert {:failure, :oversized} =
             TransferAdmission.joint_admit(
               candidate([ordinary, transfer]),
               context(),
               host(%{check: check})
             )

    refute_received {:checked_oversized, _}
  end

  test "speech without transfer runs only the after-turn check" do
    parent = self()

    check = fn _server, event, proposal, _evidence, _deadline ->
      send(parent, {:checked, event, proposal})
      :passed
    end

    speech_only = candidate([tool_call("ordinary-1", "lookup_order")])

    assert {:accept, %{binds: []}} =
             TransferAdmission.joint_admit(speech_only, context(), host(%{check: check}))

    assert_received {:checked, :after_turn, "turn-1:1"}
    refute_received {:checked, :before_outgoing_transfer, _}
  end

  test "empty question lists skip every check" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      flunk("no check must run without configured questions")
    end

    no_questions = host(%{after_questions: [], transfer_questions: [], check: check})

    assert {:accept, %{binds: []}} =
             TransferAdmission.joint_admit(candidate(calls()), context(), no_questions)
  end

  test "missing guardrails server fails closed when questions exist" do
    check = fn _server, _event, _proposal, _evidence, _deadline -> :passed end

    assert {:failure, :error} =
             TransferAdmission.joint_admit(
               candidate(calls()),
               context(),
               host(%{guardrails: nil, check: check})
             )
  end

  test "missing terminal kinds fail closed instead of name-matching" do
    check = fn _server, _event, _proposal, _evidence, _deadline -> :passed end

    assert {:failure, :error} =
             TransferAdmission.joint_admit(
               candidate(calls()),
               context(),
               host(%{terminal_kinds: %{}, check: check})
             )
  end

  test "joint denials count the exact serialized feedback including both events and escapes" do
    line = "Repeat \"billing\"\nplease"
    check = fn _, _, _, _, _ -> {:blocked, [line]} end

    failures = [
      %{event: :after_turn, messages: [line]},
      %{event: :before_outgoing_transfer, messages: [line]}
    ]

    bytes =
      byte_size(JSON.encode!(%{type: "guardrail_failure", status: "blocked", failures: failures}))

    admit = fn limit ->
      TransferAdmission.joint_admit(
        candidate(calls()),
        context(),
        host(%{check: check, maximum_feedback_bytes: limit})
      )
    end

    assert {:failure, :oversized} = admit.(bytes - 1)
    assert {:repair, %{failures: ^failures, messages: [^line, ^line]}} = admit.(bytes)
  end

  test "oversized repair feedback fails the round without dropping failed questions" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      {:blocked, [String.duplicate("x", 4_096)]}
    end

    assert {:failure, :oversized} =
             TransferAdmission.joint_admit(
               candidate(calls()),
               context(),
               host(%{check: check, maximum_feedback_bytes: 10})
             )
  end

  test "invalid and crashing checks fail closed without leaking internals" do
    invalid = fn _server, _event, _proposal, _evidence, _deadline -> {:blocked, :oops} end
    crashing = fn _server, _event, _proposal, _evidence, _deadline -> raise "boom" end

    assert {:failure, :error} =
             TransferAdmission.joint_admit(candidate(calls()), context(), host(%{check: invalid}))

    assert {:failure, :error} =
             TransferAdmission.joint_admit(
               candidate(calls()),
               context(),
               host(%{check: crashing})
             )
  end

  test "an elapsed response deadline fails without issuing checks" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      flunk("no check must run past the response deadline")
    end

    past = host(%{check: check, response_deadline_ms: System.monotonic_time(:millisecond) - 1})

    assert {:failure, :error} = TransferAdmission.joint_admit(candidate(calls()), context(), past)
  end

  test "invalid candidate or context fails without guardrail I/O" do
    check = fn _server, _event, _proposal, _evidence, _deadline ->
      flunk("no check must run for invalid input")
    end

    assert {:failure, :error} =
             TransferAdmission.joint_admit(%{text: "nope"}, context(), host(%{check: check}))

    assert {:failure, :error} =
             TransferAdmission.joint_admit(candidate(calls()), %{}, host(%{check: check}))
  end

  test "structured rounds check only speaker text and omit listener content from tool-only transfers" do
    observer = self()

    check = fn _server, event, _proposal, evidence, _deadline ->
      send(observer, {:checked_text, event, evidence["text"]})
      :passed
    end

    structured = %{context() | reply_protocol: :mode_message_v1}

    for {mode, message, checked} <- [
          {"speaker", "Caller-facing draft.", "Caller-facing draft."},
          {"listener", nil, ""},
          {"listener", "Private listener note.", ""}
        ] do
      envelope =
        JSON.encode!(%{
          type: "participant_message",
          participant_id: "support",
          agent_mode: mode,
          message: message
        })

      candidate =
        RoundCandidate.new(envelope,
          tool_calls: calls(),
          reply_protocol: structured.reply_protocol
        )

      assert {:accept, %{binds: [_]}} =
               TransferAdmission.joint_admit(candidate, structured, host(%{check: check}))

      assert_received {:checked_text, :before_outgoing_transfer, ^checked}

      if mode == "speaker" do
        assert_received {:checked_text, :after_turn, ^checked}
      else
        refute_received {:checked_text, :after_turn, _}
      end
    end
  end

  test "transfer evidence carries destination and invocation but no hidden payloads" do
    parent = self()

    check = fn _server, event, _proposal, evidence, _deadline ->
      send(parent, {:evidence, event, evidence})
      :passed
    end

    transfer_with_reason =
      tool_call(@transfer_call_id, "transfer", %{
        "destination" => "billing",
        "reason" => "Caller asked for billing."
      })

    ordinary = tool_call("ordinary-1", "lookup_order", %{"order_id" => "secret"})

    assert {:accept, _} =
             TransferAdmission.joint_admit(
               candidate([ordinary, transfer_with_reason]),
               context(),
               host(%{check: check})
             )

    assert_received {:evidence, :before_outgoing_transfer, evidence}
    assert evidence["destination"] == "billing"
    assert evidence["reason"] == "Caller asked for billing."
    assert evidence["invocation_id"] == @transfer_call_id
    assert evidence["attempt_id"] == "turn-1:1"
    refute Map.has_key?(evidence, "scores")
    refute Map.has_key?(evidence, "rule_ids")
    refute Enum.any?(Map.values(evidence), &match?(%{"order_id" => _}, &1))

    assert_received {:evidence, :after_turn, after_evidence}
    assert after_evidence["text"] == "I will transfer you now."
    assert after_evidence["attempt_id"] == "turn-1:1"

    for checked <- [evidence, after_evidence] do
      assert checked["proposed_calls"] == [
               %{"id" => "ordinary-1", "name" => "lookup_order", "kind" => "ordinary"},
               %{"id" => @transfer_call_id, "name" => "transfer", "kind" => "transfer"}
             ]

      refute JSON.encode!(checked) =~ "secret"
    end

    refute Enum.any?(Map.values(after_evidence), &match?(%{"order_id" => _}, &1))
  end

  test "policy digests distinguish question sets and ignore ordering" do
    questions_a = [
      %{
        id: "first",
        question: "One?",
        required_answer: :yes,
        threshold_hundredths: 70,
        response: nil
      },
      %{
        id: "second",
        question: "Two?",
        required_answer: :no,
        threshold_hundredths: 75,
        response: "No."
      }
    ]

    assert TransferAdmission.policy_digest([]) == nil

    digest_a = TransferAdmission.policy_digest(questions_a)
    assert is_binary(digest_a)
    assert TransferAdmission.policy_digest(Enum.reverse(questions_a)) == digest_a

    changed = [%{hd(questions_a) | threshold_hundredths: 71} | tl(questions_a)]
    refute TransferAdmission.policy_digest(changed) == digest_a
  end

  test "check_transfer passes through when no transfer questions are configured" do
    attrs = %{
      guardrails: nil,
      policy_digest: nil,
      activation_id: "activation-1",
      invocation_id: "transfer-1",
      incarnation_id: "incarnation-1",
      destination: "billing",
      reason: nil,
      text: "hello",
      check: fn _server, _event, _proposal, _evidence, _deadline -> flunk("must not check") end,
      deadline_ms: System.monotonic_time(:millisecond) + 2_000
    }

    assert :passed = TransferAdmission.check_transfer(attrs)

    assert :passed =
             TransferAdmission.check_transfer(%{
               attrs
               | text: nil,
                 reason: String.duplicate("x", 8193)
             })
  end

  test "check_transfer fails closed when questions exist but the service is missing" do
    attrs = %{
      guardrails: nil,
      policy_digest: "digest",
      activation_id: "activation-1",
      invocation_id: "transfer-1",
      incarnation_id: "incarnation-1",
      destination: "billing",
      reason: nil,
      text: "hello",
      check: fn _server, _event, _proposal, _evidence, _deadline -> :passed end,
      deadline_ms: System.monotonic_time(:millisecond) + 2_000
    }

    assert {:error, :unavailable} = TransferAdmission.check_transfer(attrs)
  end

  test "check_transfer uses the invocation id as proposal and maps results" do
    parent = self()

    check = fn _server, event, proposal, evidence, _deadline ->
      send(parent, {:checked, event, proposal, evidence})
      {:blocked, ["Ask which department the caller needs."]}
    end

    attrs = %{
      guardrails: :fake,
      policy_digest: "digest",
      activation_id: "activation-1",
      invocation_id: "transfer-1",
      incarnation_id: "incarnation-1",
      destination: "billing",
      reason: nil,
      text: "hello",
      check: check,
      deadline_ms: System.monotonic_time(:millisecond) + 2_000
    }

    assert {:blocked, ["Ask which department the caller needs."]} =
             TransferAdmission.check_transfer(attrs)

    assert_received {:checked, :before_outgoing_transfer, "transfer-1", evidence}
    assert evidence["destination"] == "billing"
  end

  test "a native check whose earlier deadline elapsed never starts the adapter" do
    attrs = %{
      guardrails: :tests,
      policy_digest: "one",
      invocation_id: "call",
      destination: "billing",
      deadline_ms: System.monotonic_time(:millisecond) - 1,
      check: fn _, _, _, _, _ -> :passed end
    }

    assert {:error, :timeout} = TransferAdmission.check_transfer(attrs)
  end

  test "check_transfer rejects oversized current evidence explicitly" do
    attrs = %{
      guardrails: :fake,
      policy_digest: "digest",
      activation_id: "activation-1",
      invocation_id: "transfer-1",
      incarnation_id: "incarnation-1",
      destination: "billing",
      reason: nil,
      text: String.duplicate("z", 9 * 1_024),
      check: fn _server, _event, _proposal, _evidence, _deadline -> flunk("must not check") end,
      deadline_ms: System.monotonic_time(:millisecond) + 2_000
    }

    assert {:error, :oversized} = TransferAdmission.check_transfer(attrs)
  end

  test "native transfer evidence counts UTF-8 bytes even with no speech" do
    parent = self()

    check = fn _, _, _, _, _ ->
      send(parent, :native_checked)
      :passed
    end

    attrs = %{
      guardrails: :fake,
      policy_digest: "digest",
      destination: "billing",
      reason: "a" <> String.duplicate("\u0301", 4092),
      text: nil,
      check: check
    }

    assert byte_size(attrs.destination) + byte_size(attrs.reason) == 8192
    assert :passed = TransferAdmission.check_transfer(attrs)
    assert_received :native_checked

    assert {:error, :oversized} =
             TransferAdmission.check_transfer(%{attrs | reason: attrs.reason <> "a"})

    refute_received :native_checked
  end
end
