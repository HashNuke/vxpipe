defmodule Vxpipe.CallEngine.Guardrails.EmissionFactsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.DecisionsFact

  alias Vxpipe.CallEngine.Guardrails.Emission

  setup do
    start = ~U[2026-11-28 10:00:00.000Z]
    finish = ~U[2026-11-28 10:00:00.100Z]

    first = %{
      attempt_id: "attempt-1",
      ordinal: 0,
      outcome: :failed,
      error_code: :rate_limited,
      provider: "jev",
      model: nil,
      request_id: "req-1",
      started_at: start,
      ended_at: DateTime.add(start, 12, :millisecond),
      duration_ms: 12,
      retry_of: nil,
      usage: :unknown
    }

    second = %{
      first
      | attempt_id: "attempt-2",
        ordinal: 1,
        outcome: :succeeded,
        error_code: nil,
        model: "jev-1.14.0",
        request_id: "req-2",
        retry_of: "attempt-1",
        started_at: DateTime.add(finish, -25, :millisecond),
        ended_at: finish,
        duration_ms: 25,
        usage: %{input_tokens: 1, output_tokens: 2, total_tokens: 3}
    }

    report = %{
      evaluation_id: "evaluation-1",
      event: :after_turn,
      outcome: :passed,
      source_turn_id: "source-turn",
      response_turn_id: "response-turn",
      candidate_attempt_id: "candidate-1",
      policy_revision: 7,
      policy_digest: "sha256:abc",
      selected_provider: "jev",
      selected_model: "jev-latest",
      actual_provider: "jev",
      actual_model: "jev-1.14.0",
      actual_request_id: "req-2",
      questions: [%{id: "scope", required_answer: :yes, threshold_hundredths: 70}],
      outcomes: [
        %{question_id: "scope", outcome: :passed, probability_yes: 0.9, inferred_answer: :yes}
      ],
      attempts: [first, second],
      started_at: start,
      ended_at: finish,
      duration_ms: 98
    }

    %{report: report}
  end

  test "records turn links, selected and returned models, and separate gate and attempt timings",
       %{report: report} do
    assert {:ok, evaluation} = Emission.evaluation_fact(report, %{})

    assert %{
             "evaluation_id" => "evaluation-1",
             "event" => "after_turn",
             "outcome" => "passed",
             "policy_revision" => 7,
             "policy_digest" => "sha256:abc",
             "attempt_ids" => ["attempt-1", "attempt-2"],
             "source_turn_id" => "source-turn",
             "response_turn_id" => "response-turn",
             "candidate_attempt_id" => "candidate-1",
             "selected_provider" => "jev",
             "selected_model" => "jev-latest",
             "actual_provider" => "jev",
             "actual_model" => "jev-1.14.0",
             "actual_request_id" => "req-2",
             "question_ids" => ["scope"],
             "started_at" => "2026-11-28T10:00:00.000Z",
             "ended_at" => "2026-11-28T10:00:00.100Z",
             "duration_ms" => 98
           } = evaluation[:payload]

    assert evaluation[:correlation_id] == "response-turn"

    assert {:ok, [decisions_attempt: initial, decisions_attempt: retry]} =
             Emission.attempt_facts(report, %{})

    assert %{
             "evaluation_id" => "evaluation-1",
             "attempt_id" => "attempt-1",
             "ordinal" => 0,
             "event" => "after_turn",
             "outcome" => "failed",
             "error_code" => "rate_limited",
             "policy_digest" => "sha256:abc",
             "model" => nil,
             "duration_ms" => 12,
             "retry_of" => nil
           } = initial[:payload]

    assert %{
             "evaluation_id" => "evaluation-1",
             "attempt_id" => "attempt-2",
             "ordinal" => 1,
             "outcome" => "succeeded",
             "policy_revision" => 7,
             "provider" => "jev",
             "model" => "jev-1.14.0",
             "request_id" => "req-2",
             "retry_of" => "attempt-1",
             "started_at" => "2026-11-28T10:00:00.075Z",
             "ended_at" => "2026-11-28T10:00:00.100Z",
             "duration_ms" => 25
           } = retry[:payload]
  end

  test "carries only bounded error codes from terminal reports into history", %{report: report} do
    [initial | _] = report.attempts

    for code <- [:unauthorized, :transport_error] do
      failed = %{report | outcome: :error, attempts: [%{initial | error_code: code}]}
      failed = Map.put(failed, :error_code, code)
      assert {:ok, evaluation} = Emission.evaluation_fact(failed, %{})
      assert {:ok, [decisions_attempt: attempt]} = Emission.attempt_facts(failed, %{})
      assert evaluation[:payload]["error_code"] == Atom.to_string(code)
      assert attempt[:payload]["error_code"] == Atom.to_string(code)
      assert :ok = DecisionsFact.validate(:decisions_evaluation, evaluation[:payload])
      assert :ok = DecisionsFact.validate(:decisions_attempt, attempt[:payload])
    end

    unsafe = %{report | attempts: [%{initial | error_code: "raw provider failure"}]}
    assert {:error, :invalid_decisions_report} = Emission.attempt_facts(unsafe, %{})

    assert {:ok, [{:decisions_attempt, attempt} | _]} = Emission.attempt_facts(report, %{})

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_attempt,
               Map.put(attempt[:payload], "error_code", "raw provider failure")
             )
  end
end
