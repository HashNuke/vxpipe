defmodule Vxpipe.CallEngine.Archive.DecisionsFact do
  @moduledoc "Validates the private, version-pinned Decisions facts stored in call history."

  @kinds [:decisions_evaluation, :decisions_question_result, :decisions_attempt]
  @events ~w(before_turn after_turn before_outgoing_transfer)
  @errors ~w(timeout unavailable unauthorized transport_error rate_limited invalid_result refused oversized retry_exhausted stale cancelled)
  @common ~w(evaluation_id policy_digest policy_revision content_unavailable)
  @timing ~w(started_at ended_at duration_ms)
  @evaluation_ids ~w(transfer_invocation_id source_turn_id response_turn_id candidate_attempt_id selected_provider selected_model actual_provider actual_model actual_request_id)
  @attempt_ids ~w(provider model request_id retry_of)
  @question_content ~w(question response feedback)
  @fields %{
    decisions_evaluation:
      @common ++
        @timing ++ @evaluation_ids ++ ~w(event outcome error_code attempt_ids question_ids),
    decisions_question_result:
      @common ++
        @question_content ++
        ~w(question_id ordinal required_answer threshold_hundredths outcome probability_yes inferred_answer feedback_origin feedback_dispatched),
    decisions_attempt:
      @common ++ @timing ++ @attempt_ids ++ ~w(attempt_id event outcome error_code ordinal)
  }

  @spec validate(atom(), map()) :: :ok | {:error, :invalid_call_fact}
  def validate(kind, payload) when kind in @kinds and is_map(payload) do
    valid =
      Enum.all?(Map.keys(payload), &(&1 in Map.fetch!(@fields, kind))) and
        id?(payload["evaluation_id"], 128) and
        match?("sha256:" <> _, payload["policy_digest"]) and
        valid_marker?(payload["content_unavailable"]) and valid_payload?(kind, payload)

    if valid, do: :ok, else: {:error, :invalid_call_fact}
  end

  def validate(kind, _payload) when kind in @kinds, do: {:error, :invalid_call_fact}
  def validate(_kind, _payload), do: :ok

  defp valid_payload?(:decisions_evaluation, p) do
    attempts = Map.get(p, "attempt_ids", [])

    p["event"] in @events and
      p["outcome"] in ~w(passed blocked error cancelled skipped_empty not_applicable) and
      nonnegative?(p["policy_revision"]) and p["error_code"] in [nil | @errors] and
      optional_ids?(p, @evaluation_ids) and valid_timing?(p) and
      (p["event"] != "before_outgoing_transfer" or id?(p["transfer_invocation_id"])) and
      id_list?(attempts) and (p["outcome"] not in ["passed", "blocked"] or attempts != []) and
      (is_nil(p["question_ids"]) or id_list?(p["question_ids"]))
  end

  defp valid_payload?(:decisions_question_result, p) do
    id?(p["question_id"]) and nonnegative?(p["ordinal"]) and nonnegative?(p["policy_revision"]) and
      p["required_answer"] in ["yes", "no"] and p["threshold_hundredths"] in 0..100 and
      p["outcome"] in ~w(passed failed unavailable) and
      Enum.all?(@question_content, &(is_nil(p[&1]) or is_binary(p[&1]))) and
      p["feedback_origin"] in [nil, "configured", "authored", "fallback"] and
      p["feedback_dispatched"] in [nil, true, false] and valid_score?(p)
  end

  defp valid_payload?(:decisions_attempt, p) do
    id?(p["attempt_id"], 128) and nonnegative?(p["ordinal"]) and
      p["event"] in @events and p["outcome"] in ~w(succeeded failed cancelled) and
      p["error_code"] in [nil | @errors] and
      (is_nil(p["policy_revision"]) or nonnegative?(p["policy_revision"])) and
      optional_ids?(p, @attempt_ids) and valid_timing?(p)
  end

  defp valid_marker?(nil), do: true

  defp valid_marker?(%{"reason" => reason} = marker),
    do: map_size(marker) == 1 and reason in ["denied", "unknown"]

  defp valid_marker?(_), do: false

  defp valid_score?(%{"content_unavailable" => marker} = p) when is_map(marker) do
    Enum.all?(
      @question_content ++ ~w(probability_yes inferred_answer feedback_origin),
      &is_nil(p[&1])
    ) and
      p["feedback_dispatched"] == false
  end

  defp valid_score?(%{"outcome" => "unavailable"} = p),
    do: is_nil(p["probability_yes"]) and is_nil(p["inferred_answer"])

  defp valid_score?(p),
    do:
      is_number(p["probability_yes"]) and p["probability_yes"] >= 0 and p["probability_yes"] <= 1 and
        p["inferred_answer"] in ["yes", "no"]

  defp valid_timing?(p) do
    Enum.all?(~w(started_at ended_at), &(is_nil(p[&1]) or is_binary(p[&1]))) and
      (is_nil(p["duration_ms"]) or nonnegative?(p["duration_ms"]))
  end

  defp nonnegative?(n), do: is_integer(n) and n >= 0
  defp optional_ids?(p, fields), do: Enum.all?(fields, &(is_nil(p[&1]) or id?(p[&1])))
  defp id_list?(ids), do: is_list(ids) and Enum.all?(ids, &id?/1)
  defp id?(value, max \\ 256), do: is_binary(value) and byte_size(value) in 1..max
end
