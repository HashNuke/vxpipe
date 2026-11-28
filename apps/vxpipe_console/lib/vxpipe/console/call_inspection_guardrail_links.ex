defmodule Vxpipe.Console.CallInspectionGuardrailLinks do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.MessagePayload

  def index(facts, evaluations) do
    records =
      facts
      |> Enum.flat_map(&records/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # Identical text can occur in more than one accepted candidate on a turn.
    # Only a unique candidate can claim its delivery receipt.
    candidates =
      for fact <- evaluations,
          fact.payload["event"] == "after_turn" and fact.payload["outcome"] == "passed",
          is_binary(fact.payload["checked_text"]),
          do: {output_key(fact, fact.payload["response_turn_id"]), fact.payload["checked_text"]}

    %{records: records, candidates: Enum.frequencies(candidates)}
  end

  def for_evaluation(evaluation, index) do
    if is_binary(evaluation.command_id),
      do: links(evaluation.payload["event"], evaluation, index),
      else: {%{}, 0}
  end

  defp links("before_turn", fact, index) do
    key =
      {room(fact), fact.source_participant_id, fact.command_id, fact.payload["source_turn_id"]}

    case index.records[{:input, key}] do
      [%{id: id, sequence: seq}] -> {%{"message_id" => id}, seq}
      _ -> {%{}, 0}
    end
  end

  defp links(
         "after_turn",
         %{payload: %{"outcome" => "passed", "checked_text" => text}} = fact,
         index
       )
       when is_binary(text) do
    key = {output_key(fact, fact.payload["response_turn_id"]), text}

    if index.candidates[key] == 1 do
      Enum.reduce(
        [{:output, "message_id"}, {:delivered, "delivered_fact_id"}],
        {%{}, 0},
        fn {kind, field}, {fields, revision} ->
          case index.records[{kind, key}] do
            [%{id: id, sequence: seq}] -> {Map.put(fields, field, id), max(revision, seq)}
            _ -> {fields, revision}
          end
        end
      )
    else
      {%{}, 0}
    end
  end

  defp links("before_outgoing_transfer", fact, index) do
    key = output_key(fact, fact.payload["transfer_invocation_id"])

    case index.records[{:transfer, key}] do
      [result] ->
        outcome =
          if result.kind == :participant_transfer_completed, do: "completed", else: "failed"

        {%{
           "transfer_outcome" => outcome,
           "destination_participant_id" => result.payload["destination_participant_id"]
         }, result.sequence}

      _ ->
        {%{}, 0}
    end
  end

  defp links(_, _, _), do: {%{}, 0}

  defp records(%{kind: :accepted_input, correlation_id: turn} = fact) when is_binary(turn) do
    case MessagePayload.project(fact.kind, fact.payload, fact.participant_id) do
      %{text: _} -> [{{:input, {room(fact), fact.participant_id, fact.command_id, turn}}, fact}]
      nil -> []
    end
  end

  defp records(%{kind: :agent_output_generated, correlation_id: turn} = fact)
       when is_binary(turn) do
    case MessagePayload.project(fact.kind, fact.payload, fact.participant_id) do
      %{text: text} -> [{{:output, {output_key(fact, turn), text}}, fact}]
      nil -> []
    end
  end

  defp records(
         %{kind: :agent_output_delivered, correlation_id: turn, payload: %{"text" => text}} = fact
       )
       when is_binary(turn) and is_binary(text),
       do: [{{:delivered, {output_key(fact, turn), text}}, fact}]

  defp records(%{kind: kind, tool_call_id: id} = fact)
       when kind in [:participant_transfer_completed, :participant_transfer_failed] and
              is_binary(id),
       do: [{{:transfer, output_key(fact, id)}, fact}]

  defp records(_), do: []

  defp output_key(fact, turn) do
    {room(fact), fact.participant_id, fact.activation_id, fact.command_id, turn}
  end

  defp room(fact), do: {fact.tenant_key, fact.call_id, fact.room_id, fact.incarnation_id}
end
