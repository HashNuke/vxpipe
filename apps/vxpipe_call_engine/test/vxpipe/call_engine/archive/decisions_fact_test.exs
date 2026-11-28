defmodule Vxpipe.CallEngine.Archive.DecisionsFactTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Archive.DecisionsFact

  test "accepts permitted evaluation, question and attempt shapes" do
    assert :ok = DecisionsFact.validate(:decisions_evaluation, evaluation_payload())
    assert :ok = DecisionsFact.validate(:decisions_question_result, question_payload())
    assert :ok = DecisionsFact.validate(:decisions_attempt, attempt_payload())
  end

  test "retains typed provider authentication and connection failures in history" do
    for code <- ["unauthorized", "transport_error"] do
      evaluation = Map.merge(evaluation_payload(), %{"outcome" => "error", "error_code" => code})
      attempt = Map.merge(attempt_payload(), %{"outcome" => "failed", "error_code" => code})
      assert :ok = DecisionsFact.validate(:decisions_evaluation, evaluation)
      assert :ok = DecisionsFact.validate(:decisions_attempt, attempt)
    end
  end

  test "rejects unknown top-level keys at the boundary" do
    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_question_result,
               Map.put(question_payload(), "smuggled", "private")
             )

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_evaluation,
               Map.put(evaluation_payload(), "question", "Is the caller private?")
             )

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_attempt,
               Map.put(attempt_payload(), "evidence", [%{"candidate" => "private"}])
             )
  end

  test "rejects nested private content even when top-level keys are known" do
    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_question_result,
               Map.put(question_payload(), "outer", %{"question" => "smuggled"})
             )

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(
               :decisions_evaluation,
               Map.put(evaluation_payload(), "outer", [%{"feedback" => "smuggled"}])
             )
  end

  test "rejects unidentified extra evidence inside the permission marker and turn links" do
    marker = %{"reason" => "denied", "extra" => "private source text"}

    for fields <- [%{"content_unavailable" => marker}, %{"transfer_invocation_id" => marker}] do
      assert {:error, :invalid_call_fact} =
               DecisionsFact.validate(
                 :decisions_evaluation,
                 Map.merge(evaluation_payload(), fields)
               )
    end
  end

  test "accepts the denied-interval shape with nil scores and unavailable marker" do
    denied =
      question_payload()
      |> Map.merge(%{
        "question" => nil,
        "response" => nil,
        "feedback" => nil,
        "probability_yes" => nil,
        "inferred_answer" => nil,
        "feedback_origin" => nil,
        "feedback_dispatched" => false,
        "content_unavailable" => %{"reason" => "denied"}
      })
      |> Map.delete("question")
      |> Map.delete("response")
      |> Map.delete("feedback")

    assert :ok = DecisionsFact.validate(:decisions_question_result, denied)
  end

  test "rejects denied markers mixed with private content or scores" do
    denied_with_text =
      question_payload()
      |> Map.put("content_unavailable", %{"reason" => "denied"})

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(:decisions_question_result, denied_with_text)

    denied_with_score =
      question_payload()
      |> Map.merge(%{
        "probability_yes" => nil,
        "inferred_answer" => nil,
        "feedback_origin" => nil,
        "feedback_dispatched" => false,
        "content_unavailable" => %{"reason" => "denied"},
        "outer" => %{"messages" => ["private"]}
      })
      |> Map.delete("question")

    assert {:error, :invalid_call_fact} =
             DecisionsFact.validate(:decisions_question_result, denied_with_score)
  end

  defp evaluation_payload do
    %{
      "evaluation_id" => "eval-1",
      "event" => "before_turn",
      "outcome" => "blocked",
      "policy_digest" => "sha256:abc",
      "policy_revision" => 3,
      "attempt_ids" => ["attempt-1"]
    }
  end

  defp question_payload do
    %{
      "evaluation_id" => "eval-1",
      "question_id" => "private_request",
      "ordinal" => 0,
      "required_answer" => "yes",
      "threshold_hundredths" => 70,
      "outcome" => "passed",
      "probability_yes" => 0.8,
      "inferred_answer" => "yes",
      "policy_revision" => 3,
      "policy_digest" => "sha256:abc"
    }
  end

  defp attempt_payload do
    %{
      "evaluation_id" => "eval-1",
      "attempt_id" => "attempt-1",
      "event" => "before_turn",
      "outcome" => "succeeded",
      "ordinal" => 0,
      "policy_digest" => "sha256:abc"
    }
  end
end
