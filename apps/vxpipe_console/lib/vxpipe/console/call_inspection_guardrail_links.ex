defmodule Vxpipe.Console.CallInspectionGuardrailLinks do
  @moduledoc false

  alias Vxpipe.CallEngine.Archive.MessagePayload

  def index(facts, evaluations) do
    records =
      facts
      |> Enum.flat_map(&records/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    # Two attempts may produce the same speech. A failed joint gate excludes
    # that entire candidate from the set that could own a delivery.
    vetoes =
      for fact <- evaluations,
          fact.payload["event"] == "before_outgoing_transfer",
          fact.payload["outcome"] in ["blocked", "error", "cancelled"],
          is_binary(fact.command_id) and is_binary(fact.activation_id),
          is_binary(fact.payload["candidate_attempt_id"]),
          into: %{},
          do: {output_key(fact, fact.payload["candidate_attempt_id"]), fact.sequence}

    candidates =
      for fact <- evaluations,
          fact.payload["event"] == "after_turn" and fact.payload["outcome"] == "passed",
          is_binary(fact.payload["checked_text"]) do
        key = {output_key(fact, fact.payload["response_turn_id"]), fact.payload["checked_text"]}
        veto = vetoes[output_key(fact, fact.payload["candidate_attempt_id"])]
        {key, {fact.id, fact.sequence, veto}}
      end

    %{records: records, candidates: Enum.group_by(candidates, &elem(&1, 0), &elem(&1, 1))}
  end

  def for_evaluation(evaluation, index) do
    if is_binary(evaluation.command_id),
      do: links(evaluation.payload["event"], evaluation, index),
      else: {%{}, []}
  end

  defp links("before_turn", fact, index) do
    key =
      {room(fact), fact.source_participant_id, fact.command_id, fact.payload["source_turn_id"]}

    records = Map.get(index.records, {:input, key}, [])

    fields =
      case records do
        [entry] -> %{"message_id" => entry.id}
        _ -> %{}
      end

    {fields, sequences(records)}
  end

  defp links(
         "after_turn",
         %{payload: %{"outcome" => "passed", "checked_text" => text}} = fact,
         index
       )
       when is_binary(text) do
    key = {output_key(fact, fact.payload["response_turn_id"]), text}

    candidates = Map.get(index.candidates, key, [])
    eligible = for {id, _, nil} <- candidates, do: id
    related = for {_, seq, veto} <- candidates, value <- [seq, veto], is_integer(value), do: value

    Enum.reduce(
      [{:output, "message_id"}, {:delivered, "delivered_fact_id"}],
      {%{}, related},
      fn {kind, field}, {fields, revisions} ->
        records = Map.get(index.records, {kind, key}, [])

        fields =
          case records do
            [record] when eligible == [fact.id] -> Map.put(fields, field, record.id)
            _ -> fields
          end

        {fields, sequences(records) ++ revisions}
      end
    )
  end

  defp links("before_outgoing_transfer", fact, index) do
    key = output_key(fact, fact.payload["transfer_invocation_id"])

    records = Map.get(index.records, {:transfer, key}, [])

    fields =
      case records do
        [result] ->
          %{
            "transfer_outcome" =>
              if(result.kind == :participant_transfer_completed, do: "completed", else: "failed"),
            "destination_participant_id" => result.payload["destination_participant_id"]
          }

        _ ->
          %{}
      end

    {fields, sequences(records)}
  end

  defp links(_, _, _), do: {%{}, []}

  defp sequences(records), do: Enum.map(records, & &1.sequence)

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
