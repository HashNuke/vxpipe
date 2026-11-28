defmodule Vxpipe.Calls.ArchiveSanitizerTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls.ArchiveSanitizer

  test "denied and unknown guardrail intervals remove the proposed destination and tool identities" do
    payload = %{
      "requested_destination" => "billing",
      "proposed_calls" => [%{"id" => "tool", "name" => "lookup"}]
    }

    for policy <- [%{}, %{"save_transcripts" => false}] do
      filtered = ArchiveSanitizer.filter_payload(payload, :decisions_evaluation, policy)
      refute Map.has_key?(filtered, "requested_destination")
      refute Map.has_key?(filtered, "proposed_calls")
    end
  end

  test "transcript retention applies to nested dialogue, cues, summaries and raw copies" do
    payload = %{
      "content" => %{"message" => "private"},
      "metadata" => [
        %{
          "message" => "private",
          "summary" => "private",
          "cue" => %{"text" => "private"},
          "raw_response" => "{\"message\":\"private\"}",
          "id" => "kept"
        }
      ]
    }

    assert ArchiveSanitizer.filter_payload(payload, :agent_output_generated, %{
             "save_transcripts" => false
           }) ==
             %{"metadata" => [%{"id" => "kept"}]}

    assert ArchiveSanitizer.filter_payload(payload, :agent_output_generated, %{
             "save_transcripts" => true
           }) == payload

    assert ArchiveSanitizer.filter_payload(payload, :tool_call_completed, %{
             "save_transcripts" => false
           }) == payload
  end

  test "decisions denial strips nested private content and filters attempts" do
    denied = %{"save_transcripts" => false}

    payload = %{
      "evaluation_id" => "eval-1",
      "question" => "Is the caller asking about their own account?",
      "response" => "private response",
      "feedback" => "private feedback",
      "nested" => %{
        "question" => "nested private",
        "evidence" => [%{"candidate" => "private draft"}]
      },
      "list" => [%{"messages" => ["private message"]}]
    }

    filtered = ArchiveSanitizer.filter_payload(payload, :decisions_evaluation, denied)

    assert filtered["content_unavailable"] == %{"reason" => "denied"}
    assert filtered["evaluation_id"] == "eval-1"
    refute JSON.encode!(filtered) =~ "private"

    question =
      ArchiveSanitizer.filter_payload(
        Map.put(payload, "probability_yes", 0.3),
        :decisions_question_result,
        denied
      )

    assert question["content_unavailable"] == %{"reason" => "denied"}
    assert question["probability_yes"] == nil
    assert question["inferred_answer"] == nil
    refute JSON.encode!(question) =~ "private"

    attempt =
      ArchiveSanitizer.filter_payload(
        %{
          "evaluation_id" => "eval-1",
          "attempt_id" => "attempt-1",
          "question" => "private",
          "nested" => %{"draft" => "private"}
        },
        :decisions_attempt,
        denied
      )

    assert attempt["content_unavailable"] == %{"reason" => "denied"}
    assert attempt["attempt_id"] == "attempt-1"
    refute JSON.encode!(attempt) =~ "private"

    assert ArchiveSanitizer.filter_payload(payload, :decisions_evaluation, %{
             "save_transcripts" => true
           }) == payload

    assert ArchiveSanitizer.filter_payload(payload, :decisions_attempt, %{
             "save_transcripts" => true
           }) == payload
  end
end
