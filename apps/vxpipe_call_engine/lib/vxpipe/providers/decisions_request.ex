defmodule Vxpipe.Providers.DecisionsRequest do
  @moduledoc false
  @max_bytes 48 * 1_024
  @id_pattern ~r/\A[a-z][a-z0-9_]{0,63}\z/

  def build(evidence, questions, format, build_body) when is_list(questions) do
    with {:ok, input} <- input(evidence, format),
         {:ok, pairs} <- ordered_questions(questions) do
      body = build_body.(input, pairs)
      if byte_size(JSON.encode!(body)) <= @max_bytes, do: {:ok, body}, else: {:error, :oversized}
    end
  rescue
    _ in [Protocol.UndefinedError, ArgumentError] -> {:error, :invalid_request}
  end

  def build(_evidence, _questions, _format, _build_body), do: {:error, :invalid_request}

  defp input(evidence, _format) when is_binary(evidence) do
    cond do
      byte_size(evidence) > @max_bytes -> {:error, :oversized}
      evidence == "" or not String.valid?(evidence) -> {:error, :invalid_request}
      true -> {:ok, evidence}
    end
  end

  defp input(evidence, :text) when is_map(evidence), do: {:ok, JSON.encode!(evidence)}
  defp input(evidence, :state) when is_map(evidence), do: {:ok, evidence}
  defp input(_evidence, _format), do: {:error, :invalid_request}

  defp ordered_questions(questions) when length(questions) not in 1..32, do: {:error, :oversized}

  defp ordered_questions(questions) do
    pairs = Enum.map(questions, &pair/1)

    if Enum.all?(pairs, &valid_pair?/1) and Enum.uniq_by(pairs, &elem(&1, 0)) == pairs,
      do: {:ok, pairs},
      else: {:error, :invalid_request}
  end

  defp pair(%{id: id, question: text}), do: {id, text}
  defp pair(%{"id" => id, "question" => text}), do: {id, text}
  defp pair(_question), do: nil

  defp valid_pair?({id, text}) when is_binary(id) and is_binary(text) do
    byte_size(text) in 1..1_024 and String.valid?(text) and Regex.match?(@id_pattern, id)
  end

  defp valid_pair?(_invalid), do: false
end
