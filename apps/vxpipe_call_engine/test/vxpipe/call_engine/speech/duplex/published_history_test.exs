defmodule Vxpipe.CallEngine.Speech.Duplex.PublishedHistoryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Duplex.PublishedHistory

  test "keeps only the most recent 128 published messages" do
    history =
      Enum.reduce(1..130, PublishedHistory.new(), fn number, history ->
        PublishedHistory.append(history, {:caller, Integer.to_string(number)})
      end)

    input = PublishedHistory.input(history)
    assert length(input) == 128
    assert get_in(hd(input), ["content", Access.at(0), "text"]) == "3"
    assert get_in(List.last(input), ["content", Access.at(0), "text"]) == "130"
    assert hd(input)["role"] == "user"
  end

  test "trims oldest text by the 8192-token estimate and keeps role order" do
    long = String.duplicate("x", 20_000)
    history = PublishedHistory.new()
    history = PublishedHistory.append(history, {:caller, long})
    history = PublishedHistory.append(history, {:agent, long})
    input = PublishedHistory.input(history)
    assert length(input) == 1
    assert hd(input)["role"] == "assistant"
    assert PublishedHistory.tokens(history) <= 8_192
    assert PublishedHistory.append(history, {:agent, ""}) == history
  end
end
