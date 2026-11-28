defmodule Vxpipe.Console.CallInspectionGuardrailUsage do
  @moduledoc false

  alias Vxpipe.Calls.{UsageAggregation, UsageReport}
  @tokens ~w(input_tokens output_tokens total_tokens)

  def by_attempt({:available, %UsageReport{amounts: amounts}}) do
    amounts
    |> Enum.filter(&(&1.capability == :decisions and measured?(&1)))
    |> Enum.group_by(fn amount ->
      a = amount.attribution

      {a.room_id, a.incarnation_id, a.participant_id, a.activation_id, a.turn_id, a.tool_call_id,
       amount.attempt_id}
    end)
  end

  def by_attempt(_usage), do: %{}

  def fields(fact, evaluation, index, sequences) do
    turn =
      case evaluation.payload["event"] do
        "before_turn" ->
          evaluation.payload["source_turn_id"]

        "after_turn" ->
          evaluation.payload["response_turn_id"]

        "before_outgoing_transfer" ->
          evaluation.payload["response_turn_id"] || evaluation.payload["source_turn_id"]
      end

    key =
      {fact.room_id, fact.incarnation_id, fact.participant_id, fact.activation_id, turn,
       fact.tool_call_id, fact.payload["attempt_id"]}

    amounts = Map.get(index, key, [])
    {tokens, charges} = Enum.split_with(amounts, &(&1.unit == :tokens))

    counts =
      tokens
      |> Enum.group_by(& &1.component)
      |> Map.new(fn
        {component, [amount]} -> {component, amount.quantity}
        {component, _ambiguous} -> {component, nil}
      end)

    costs = charges |> UsageAggregation.derive() |> Enum.group_by(& &1.unit)

    prices =
      for {{:currency, currency}, [total]} <- Enum.sort(costs),
          do: %{"currency" => currency, "amount" => Decimal.to_string(total.quantity, :normal)}

    fields = if prices == [], do: counts, else: Map.put(counts, "costs", prices)

    revision =
      for a <- amounts, observation <- a.observation_ids, do: Map.get(sequences, observation, 0)

    {fields, Enum.max(revision, fn -> 0 end)}
  end

  defp measured?(%{unit: :tokens, component: component, provenance: :provider_reported})
       when component in @tokens, do: true

  defp measured?(%{unit: {:currency, _}, included_in: nil, provenance: source, status: status})
       when source in [:provider_reported, :billing_lookup] and status in [:final, :correction],
       do: true

  defp measured?(_), do: false
end
