defmodule Vxpipe.Console.CallInspectionGuardrails do
  @moduledoc "Projects permission-filtered evaluations and their physical attempts from one call."

  alias Vxpipe.Calls.CallHistory
  alias Vxpipe.Console.{CallInspectionGuardrailLinks, CallInspectionGuardrailUsage}

  @evaluation ~w(event outcome error_code source_turn_id response_turn_id candidate_attempt_id
    transfer_invocation_id selected_provider selected_model actual_provider actual_model actual_request_id
    policy_revision policy_digest attempt_ids started_at ended_at duration_ms)
  @question ~w(ordinal outcome required_answer threshold_hundredths question probability_yes
    inferred_answer feedback feedback_origin feedback_dispatched)
  @attempt ~w(ordinal outcome error_code provider model request_id retry_of started_at ended_at duration_ms)

  def entities(%CallHistory{} = history, usage, observation_sequences) do
    evaluations =
      Enum.filter(
        history.decisions,
        &(&1.kind == :decisions_evaluation and is_binary(&1.participant_id))
      )

    groups = Enum.group_by(history.decisions, &CallHistory.decision_key/1)
    links = CallInspectionGuardrailLinks.index(history.facts, evaluations)
    amounts = CallInspectionGuardrailUsage.by_attempt(usage)

    evaluations
    |> Enum.sort_by(& &1.sequence)
    |> Enum.map(fn evaluation ->
      children = Map.fetch!(groups, CallHistory.decision_key(evaluation))

      {link_fields, linked_sequence} =
        if is_nil(unavailable(evaluation)),
          do: CallInspectionGuardrailLinks.for_evaluation(evaluation, links),
          else: {%{}, 0}

      {attempts, usage_revision} = attempts(evaluation, children, amounts, observation_sequences)
      id = evaluation.payload["evaluation_id"]

      value =
        evaluation.payload
        |> Map.take(@evaluation)
        |> Map.merge(%{
          "id" => id,
          "participant_id" => evaluation.participant_id,
          "activation_id" => evaluation.activation_id,
          "source_participant_id" => evaluation.source_participant_id,
          "command_id" => evaluation.command_id,
          "occurred_at" => DateTime.to_iso8601(evaluation.occurred_at),
          "attempts" => attempts
        })
        |> Map.merge(evidence(evaluation, children))
        |> Map.merge(link_fields)

      sequence = Enum.max([linked_sequence, usage_revision | Enum.map(children, & &1.sequence)])
      # A lower-sequence child can fill an archive gap after the terminal receipt.
      %{"id" => id, "revision" => sequence + length(children), "value" => value}
    end)
  end

  def rewrite_receipts(%CallHistory{decisions: decisions}) do
    receipts =
      for %{kind: :decisions_feedback_dispatched} = receipt <- decisions,
          is_nil(unavailable(receipt)),
          into: %{},
          do: {CallHistory.decision_key(receipt), receipt}

    for %{
          kind: :decisions_evaluation,
          payload: %{"outcome" => "blocked", "candidate_attempt_id" => id}
        } = fact <- decisions,
        fact.payload["event"] in ["after_turn", "before_outgoing_transfer"],
        is_binary(id) and is_binary(fact.participant_id) and is_nil(unavailable(fact)),
        receipt = receipts[CallHistory.decision_key(fact)],
        do:
          {fact.participant_id, {fact.room_id, fact.incarnation_id, fact.activation_id, id},
           receipt.sequence}
  end

  defp unavailable(%{payload: %{"content_unavailable" => %{"reason" => reason}}})
       when reason in ["denied", "unknown"], do: reason

  defp unavailable(%{source_policy: %{"save_transcripts" => true}}), do: nil
  defp unavailable(%{source_policy: %{"save_transcripts" => false}}), do: "denied"
  defp unavailable(_), do: "unknown"

  defp evidence(evaluation, children) do
    case unavailable(evaluation) do
      nil ->
        questions =
          children
          |> rows(:decisions_question_result, "question_id", evaluation.payload["question_ids"])
          |> Enum.reject(&unavailable/1)
          |> Enum.map(fn q ->
            Map.take(q.payload, @question) |> Map.put("id", q.payload["question_id"])
          end)

        evidence =
          evaluation.payload
          |> Map.take(~w(checked_text question_ids requested_destination))
          |> Map.put("questions", questions)

        case evaluation.payload["proposed_calls"] do
          calls when is_list(calls) ->
            Map.put(
              evidence,
              "proposed_tools",
              for(%{"id" => id, "name" => name} <- calls, do: %{"id" => id, "name" => name})
            )

          _ ->
            evidence
        end

      reason ->
        %{"content_unavailable" => reason, "questions" => []}
    end
  end

  defp attempts(evaluation, children, amounts, sequences) do
    children
    |> rows(:decisions_attempt, "attempt_id", evaluation.payload["attempt_ids"])
    |> Enum.map_reduce(0, fn fact, revision ->
      {measurements, sequence} =
        CallInspectionGuardrailUsage.fields(fact, evaluation, amounts, sequences)

      attempt = fact.payload |> Map.take(@attempt) |> Map.put("id", fact.payload["attempt_id"])
      {Map.merge(attempt, measurements), max(revision, sequence)}
    end)
  end

  defp rows(children, kind, key, permitted) do
    children
    |> Enum.filter(&(&1.kind == kind and (is_nil(permitted) or &1.payload[key] in permitted)))
    |> Enum.sort_by(&{&1.payload["ordinal"], &1.sequence})
    |> Enum.uniq_by(& &1.payload[key])
  end
end
