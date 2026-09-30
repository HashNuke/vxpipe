defmodule Vxpipe.Providers.Cartesia.STTTurnsTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Providers.Cartesia.STTTurns

  test "cumulative updates, eager end, resume and final text retain one locally minted turn" do
    assert {:ok, state, {:ready, fields}} = STTTurns.advance(STTTurns.new(), {:ready, "c", nil})
    assert fields == [readiness: :provider_acknowledged, provider_request_id: "c"]

    assert {:ok, state, {:speech_started, fields}} =
             STTTurns.advance(state, {:speech_started, "c", nil})

    turn = Keyword.fetch!(fields, :turn_ref)
    assert is_reference(turn)

    state =
      Enum.reduce(
        [
          {:transcript, "Hello"},
          {:transcript, "Hello there"},
          {:eager_turn_ended, "Hello there"}
        ],
        state,
        fn {kind, text}, state ->
          assert {:ok, next, {^kind, fields}} = STTTurns.advance(state, {kind, "c", text})
          assert Keyword.fetch!(fields, :turn_ref) == turn
          assert Keyword.fetch!(fields, :text) == text
          next
        end
      )

    assert {:ok, state, {:turn_resumed, fields}} =
             STTTurns.advance(state, {:turn_resumed, "c", nil})

    assert Keyword.fetch!(fields, :turn_ref) == turn
    refute Keyword.has_key?(fields, :text)

    assert {:ok, state, {:turn_ended, fields}} =
             STTTurns.advance(state, {:turn_ended, "c", "Hello there again."})

    assert Keyword.fetch!(fields, :text) == "Hello there again."
    assert Keyword.fetch!(fields, :turn_ref) == turn
    assert Keyword.fetch!(fields, :endpointing) == :provider_semantic
    assert STTTurns.finished?(state)

    assert {:ok, _, {:speech_started, fields}} =
             STTTurns.advance(state, {:speech_started, "c", nil})

    refute Keyword.fetch!(fields, :turn_ref) == turn
  end

  test "rejects mismatched identity, premature events, overlap, revision and invalid resume" do
    empty = STTTurns.new()
    refute STTTurns.finished?(empty)
    assert {:ok, ready, _} = STTTurns.advance(empty, {:ready, "c", nil})
    assert {:ok, active, _} = STTTurns.advance(ready, {:speech_started, "c", nil})
    refute STTTurns.finished?(active)
    assert {:ok, updated, _} = STTTurns.advance(active, {:transcript, "c", "stable"})
    assert {:ok, eager, _} = STTTurns.advance(updated, {:eager_turn_ended, "c", "stable"})

    for {state, event} <- [
          {empty, {:speech_started, "c", nil}},
          {ready, {:ready, "c", nil}},
          {ready, {:transcript, "c", "text"}},
          {active, {:speech_started, "c", nil}},
          {active, {:turn_resumed, "c", nil}},
          {active, {:turn_ended, "other", "text"}},
          {updated, {:transcript, "c", "revision"}},
          {eager, {:eager_turn_ended, "c", "stable"}},
          {eager, {:transcript, "c", "stable again"}},
          {updated, {:turn_ended, "c", ""}}
        ] do
      assert {:error, :invalid_transition} = STTTurns.advance(state, event)
    end

    refute inspect(updated) =~ "stable"
  end
end
