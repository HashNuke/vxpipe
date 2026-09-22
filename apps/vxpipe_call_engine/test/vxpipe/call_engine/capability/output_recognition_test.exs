defmodule Vxpipe.CallEngine.Capability.OutputRecognitionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.Capability.SpeechToSpeech.OutputRecognition

  test "finals are bounded, ordered and deduplicated by segment reference" do
    first = make_ref()
    assert {:ok, state} = OutputRecognition.add(OutputRecognition.new(), first, "FIRST")
    assert {:ok, ^state} = OutputRecognition.add(state, first, "FIRST")
    assert {:error, :conflicting_final} = OutputRecognition.add(state, first, "CHANGED")
    assert {:ok, state} = OutputRecognition.add(state, make_ref(), "SECOND")
    assert OutputRecognition.text(state) == "FIRST SECOND"
    refute inspect(state) =~ "FIRST"
  end

  test "segment and byte bounds fail without truncating or retaining excess text" do
    state =
      Enum.reduce(1..64, OutputRecognition.new(), fn _, acc ->
        {:ok, next} = OutputRecognition.add(acc, make_ref(), "")
        next
      end)

    assert {:error, :recognition_overflow} = OutputRecognition.add(state, make_ref(), "")

    assert {:ok, full} =
             OutputRecognition.add(
               OutputRecognition.new(),
               make_ref(),
               String.duplicate("x", 65_536)
             )

    assert {:error, :recognition_overflow} = OutputRecognition.add(full, make_ref(), "y")
  end
end
