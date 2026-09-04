defmodule Vxpipe.Gateway.RTVI.SpokenProgress do
  @moduledoc false

  @spec split(String.t(), non_neg_integer(), pos_integer()) :: {String.t(), String.t()}
  def split(text, played_ms, total_ms)
      when is_binary(text) and is_integer(played_ms) and played_ms >= 0 and
             is_integer(total_ms) and total_ms > 0 do
    cond do
      played_ms == 0 ->
        {"", text}

      played_ms >= total_ms ->
        {text, ""}

      true ->
        graphemes = String.graphemes(text)
        target = div(length(graphemes) * played_ms, total_ms)
        split_at = word_boundary_at_or_before(graphemes, target)
        {spoken, remaining} = Enum.split(graphemes, split_at)
        {Enum.join(spoken), Enum.join(remaining)}
    end
  end

  defp word_boundary_at_or_before(graphemes, target) do
    graphemes
    |> Enum.with_index(1)
    |> Enum.reduce_while(0, fn {grapheme, index}, boundary ->
      cond do
        index > target -> {:halt, boundary}
        String.match?(grapheme, ~r/^\s$/u) -> {:cont, index}
        true -> {:cont, boundary}
      end
    end)
  end
end
