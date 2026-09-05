defmodule Vxpipe.CallEngine.Capability.SentenceAccumulatorTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Capability.SentenceAccumulator

  test "emits only sentences proven complete by later input and flushes the tail" do
    accumulator = SentenceAccumulator.new(100)

    assert {:ok, accumulator, ["One."]} = SentenceAccumulator.push(accumulator, "One. Tw")
    assert {:ok, accumulator, []} = SentenceAccumulator.push(accumulator, "o!")
    assert {:ok, ["Two!"], "One. Two!"} = SentenceAccumulator.finish(accumulator)
  end

  test "rejects invalid and oversized aggregate output" do
    accumulator = SentenceAccumulator.new(4)

    assert {:error, :invalid_response} = SentenceAccumulator.push(accumulator, <<255>>)
    assert {:error, :invalid_response} = SentenceAccumulator.push(accumulator, "12345")
  end

  test "flushes a provider-round tail while retaining complete response text" do
    assert {:ok, accumulator, []} =
             SentenceAccumulator.new(100) |> SentenceAccumulator.push("Let me check.")

    assert {:ok, accumulator, ["Let me check."]} = SentenceAccumulator.flush(accumulator)
    assert {:ok, accumulator, []} = SentenceAccumulator.push(accumulator, "It is noon.")

    assert {:ok, ["It is noon."], "Let me check. It is noon."} =
             SentenceAccumulator.finish(accumulator)
  end
end
