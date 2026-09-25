defmodule Vxpipe.CallEngine.Speech.Duplex.TurnInferenceTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Duplex.TurnInference

  test "opens a turn on the first fragment and accumulates later fragments" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)

    {inference, events} = TurnInference.input_fragment(inference, fragment("Hello", 0, 100))
    assert [speech, partial] = events
    assert {:speech_started, [turn_ref: turn]} = speech
    assert is_reference(turn)
    assert {:input_transcript, [turn_ref: ^turn, text: "Hello", final: false]} = partial

    {inference, events} = TurnInference.input_fragment(inference, fragment(" there", 100, 200))
    assert [{:input_transcript, [turn_ref: ^turn, text: "Hello there", final: false]}] = events

    assert :open = TurnInference.status(inference)
  end

  test "closes an open turn once pushed caller audio reaches the gap" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)

    {inference, [{:speech_started, [turn_ref: turn]} | _]} =
      TurnInference.input_fragment(inference, fragment("Hi", 0, 100))

    {inference, []} = TurnInference.audio_pushed(inference, 799)

    {inference, events} = TurnInference.audio_pushed(inference, 1)
    assert {:input_transcript, [turn_ref: ^turn, text: "Hi", final: true]} = Enum.at(events, 0)

    assert {:turn_ended, [turn_ref: ^turn, text: "Hi", endpointing: :inferred_gap]} =
             Enum.at(events, 1)

    assert :idle = TurnInference.status(inference)
  end

  test "closes on a timeline gap and opens a new turn for the next fragment" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)

    {inference, [{:speech_started, [turn_ref: first]} | _]} =
      TurnInference.input_fragment(inference, fragment("one", 0, 100))

    {_inference, events} = TurnInference.input_fragment(inference, fragment("two", 1000, 1100))
    assert {:input_transcript, [turn_ref: ^first, text: "one", final: true]} = Enum.at(events, 0)
    assert {:turn_ended, ended} = Enum.at(events, 1)
    assert ended[:turn_ref] == first
    assert ended[:endpointing] == :inferred_gap
    assert {:speech_started, [turn_ref: second]} = Enum.at(events, 2)
    assert second != first

    assert {:input_transcript, [turn_ref: ^second, text: "two", final: false]} =
             Enum.at(events, 3)
  end

  test "overlapping fragments stay in one turn" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)

    {inference, [{:speech_started, [turn_ref: turn]} | _]} =
      TurnInference.input_fragment(inference, fragment("I ", 0, 400))

    {inference, events} = TurnInference.input_fragment(inference, fragment("think", 350, 700))

    assert [{:input_transcript, [turn_ref: ^turn, text: "I think", final: false]}] = events
    assert :open = TurnInference.status(inference)
  end

  test "empty fragments do not open or change a turn" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)
    {inference, []} = TurnInference.input_fragment(inference, fragment("", 0, 100))
    assert :idle = TurnInference.status(inference)

    {inference, [{:speech_started, [turn_ref: turn]} | _]} =
      TurnInference.input_fragment(inference, fragment("word", 0, 100))

    {inference, []} = TurnInference.input_fragment(inference, fragment("", 100, 200))
    assert :open = TurnInference.status(inference)

    {_inference, [_, {:turn_ended, [turn_ref: ^turn, text: "word", endpointing: :inferred_gap]}]} =
      TurnInference.finish(inference)
  end

  test "session end closes an open turn exactly once" do
    {:ok, inference} = TurnInference.new(gap_ms: 800)

    {inference, [{:speech_started, [turn_ref: turn]} | _]} =
      TurnInference.input_fragment(inference, fragment("cut", 0, 100))

    {inference, events} = TurnInference.finish(inference)
    assert {:input_transcript, [turn_ref: ^turn, text: "cut", final: true]} = Enum.at(events, 0)

    assert {:turn_ended, [turn_ref: ^turn, text: "cut", endpointing: :inferred_gap]} =
             Enum.at(events, 1)

    assert {_inference, []} = TurnInference.finish(inference)
  end

  test "rejects malformed fragments and non-positive gaps" do
    assert {:error, :invalid_gap} = TurnInference.new(gap_ms: 0)
    assert {:error, :invalid_gap} = TurnInference.new(gap_ms: -1)

    {:ok, inference} = TurnInference.new()

    {inference, []} =
      TurnInference.input_fragment(inference, %{text: "x", start_ms: 10, end_ms: 5})

    {inference, []} =
      TurnInference.input_fragment(inference, %{text: nil, start_ms: 0, end_ms: 5})

    assert :idle = TurnInference.status(inference)
  end

  defp fragment(text, start_ms, end_ms),
    do: %{text: text, start_ms: start_ms, end_ms: end_ms}
end
