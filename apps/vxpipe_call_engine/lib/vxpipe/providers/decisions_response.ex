defmodule Vxpipe.Providers.DecisionsResponse do
  @moduledoc false

  alias Vxpipe.Providers.DecisionsTransport

  def nouls(body, ids, usage, refusal \\ false) do
    answers = body["answers"]

    scores =
      for id <- ids,
          is_map(answers),
          %{"type" => "noul", "noul" => score} <- [answers[id]],
          valid_score?(score),
          into: %{},
          do: {id, score * 1.0}

    complete =
      is_map(answers) and map_size(answers) == length(ids) and map_size(scores) == length(ids)

    result(body, usage, scores, complete, refusal)
  end

  def predicates(body, ids, usage) do
    answers = body["answers"]

    if is_list(answers) do
      # Duplicate names make every score for that question ambiguous.
      by_name =
        Enum.group_by(answers, fn
          %{"name" => name} -> name
          _ -> nil
        end)

      scores =
        for id <- ids,
            [%{"type" => "predicate", "probability" => score}] <- [by_name[id]],
            valid_score?(score),
            into: %{},
            do: {id, score * 1.0}

      exact_names = length(answers) == length(ids) and Enum.all?(ids, &Map.has_key?(by_name, &1))
      refused = exact_names and Enum.any?(answers, &match?(%{"type" => "refusal"}, &1))
      result(body, usage, scores, exact_names and map_size(scores) == length(ids), refused)
    else
      result(body, usage, %{}, false, false)
    end
  end

  defp result(body, usage, scores, complete, refused) do
    model = body["model"]

    result = %{
      model: if(is_binary(model) and byte_size(model) in 1..256, do: model),
      request_id: DecisionsTransport.extract_request_id(body),
      probabilities: if(map_size(scores) > 0, do: scores),
      usage: usage
    }

    cond do
      refused -> {:error, :refused, result}
      complete -> {:ok, result}
      true -> {:error, :invalid_result, result}
    end
  end

  defp valid_score?(score), do: is_number(score) and score >= 0 and score <= 1
end
