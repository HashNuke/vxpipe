defmodule Vxpipe.MCP.AuthenticationChallenge do
  @moduledoc false

  # cowlib validates challenge syntax, but the pinned parser rejects RFC 9110
  # auth-param BWS around '='. Remove only that unquoted whitespace before parsing.
  # The pinned parser also requires nonempty scheme parameters. Split only at
  # unquoted commas to recognize bare Bearer challenges without inventing params
  # or attaching the following challenge's params to the bare scheme.
  def parse(value) do
    case value |> normalize(false, []) |> segments(false, [], []) |> parse_segments([], []) do
      [] -> raise ArgumentError, "empty authentication challenge"
      challenges -> challenges
    end
  end

  defp parse_segments([], pending, parsed),
    do: Enum.reverse(parsed) ++ parse_pending(pending)

  defp parse_segments([segment | rest], pending, parsed) do
    cond do
      Regex.match?(~r/\A[ \t]*\z/, segment) ->
        parse_segments(rest, pending, parsed)

      Regex.match?(~r/\A[ \t]*(?i:bearer)[ \t]*\z/, segment) ->
        parsed = [{:bearer, []} | Enum.reverse(parse_pending(pending), parsed)]
        parse_segments(rest, [], parsed)

      true ->
        parse_segments(rest, [segment | pending], parsed)
    end
  end

  defp parse_pending([]), do: []

  defp parse_pending(pending),
    do: pending |> Enum.reverse() |> Enum.join(",") |> :cow_http_hd.parse_www_authenticate()

  defp segments(<<>>, _quoted, acc, result),
    do: Enum.reverse([bytes(acc) | result])

  defp segments(<<?\\, escaped, rest::binary>>, true, acc, result),
    do: segments(rest, true, [escaped, ?\\ | acc], result)

  defp segments(<<?", rest::binary>>, quoted, acc, result),
    do: segments(rest, not quoted, [?" | acc], result)

  defp segments(<<?,, rest::binary>>, false, acc, result),
    do: segments(rest, false, [], [bytes(acc) | result])

  defp segments(<<byte, rest::binary>>, quoted, acc, result),
    do: segments(rest, quoted, [byte | acc], result)

  defp bytes(acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()

  defp normalize(<<>>, _quoted, acc), do: acc |> Enum.reverse() |> :erlang.list_to_binary()

  defp normalize(<<?\\, escaped, rest::binary>>, true, acc),
    do: normalize(rest, true, [escaped, ?\\ | acc])

  defp normalize(<<?", rest::binary>>, quoted, acc), do: normalize(rest, not quoted, [?" | acc])

  defp normalize(<<?=, rest::binary>>, false, acc),
    do: normalize(skip_whitespace(rest), false, [?= | Enum.drop_while(acc, &(&1 in [32, 9]))])

  defp normalize(<<byte, rest::binary>>, quoted, acc), do: normalize(rest, quoted, [byte | acc])

  defp skip_whitespace(<<byte, rest::binary>>) when byte in [32, 9], do: skip_whitespace(rest)
  defp skip_whitespace(rest), do: rest
end
