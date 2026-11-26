defmodule Vxpipe.CallEngine.Speech.LocalTurnEndTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.{Event, LocalTurnEnd}

  test "silence after speech waits for the resume window, finalizes, then ends on final text" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    native = make_ref()

    {state, [{:transcript, [turn_ref: ^turn, text: "book a table"]}], []} =
      ok(LocalTurnEnd.native(state, transcript(native, "book a table")))

    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, [], [:finalize, :arm_final_wait]} = ok(LocalTurnEnd.hangover_elapsed(state))

    assert {:ok, _state,
            [
              {:transcript, [turn_ref: ^turn, text: "book a table for two"]},
              {:turn_ended,
               [turn_ref: ^turn, text: "book a table for two", endpointing: :local_gap]}
            ], [:cancel_timers]} =
             LocalTurnEnd.native(state, ended(native, "book a table for two"))
  end

  test "speech resuming inside the resume window keeps one turn and joins provider segments" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    first = make_ref()
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, transcript(first, "I want")))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, ended(first, "I want")))
    {state, [], [:cancel_timers]} = ok(LocalTurnEnd.acoustic_started(state))

    # A stale timer from the cancelled window has no effect.
    {state, [], []} = ok(LocalTurnEnd.hangover_elapsed(state))
    second = make_ref()

    {state, [{:transcript, [turn_ref: ^turn, text: "I want a table"]}], []} =
      ok(LocalTurnEnd.native(state, transcript(second, "a table")))

    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, [], [:finalize, :arm_final_wait]} = ok(LocalTurnEnd.hangover_elapsed(state))

    assert {:ok, _state, [{:turn_ended, [turn_ref: ^turn, text: "I want a table"] ++ _}], _} =
             LocalTurnEnd.native(state, ended(second, ""))
  end

  test "a provider end inside the turn is a segment, not a turn end" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, _}], []} = ok(LocalTurnEnd.acoustic_started(state))
    native = make_ref()

    {_state, [{:transcript, [turn_ref: _turn, text: "hello"]}], []} =
      ok(LocalTurnEnd.native(state, ended(native, "hello")))
  end

  test "an already final segment ends the turn when the resume window elapses" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, ended(make_ref(), "yes")))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))

    assert {:ok, _state, [{:turn_ended, [turn_ref: ^turn, text: "yes", endpointing: :local_gap]}],
            [:cancel_timers]} = LocalTurnEnd.hangover_elapsed(state)
  end

  test "providers without finalize wait for their own final text" do
    state = LocalTurnEnd.new(finalize?: false)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    native = make_ref()
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, transcript(native, "hi")))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, [], [:arm_final_wait]} = ok(LocalTurnEnd.hangover_elapsed(state))

    assert {:ok, _state, [{:turn_ended, [turn_ref: ^turn, text: "hi", endpointing: :local_gap]}],
            [:cancel_timers]} = LocalTurnEnd.native(state, ended(native, "hi"))
  end

  test "a missing final ends the turn with the latest text once the bounded wait expires" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    native = make_ref()
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, transcript(native, "partial words")))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, [], [:finalize, :arm_final_wait]} = ok(LocalTurnEnd.hangover_elapsed(state))

    {state, [{:turn_ended, [turn_ref: ^turn, text: "partial words", endpointing: :local_gap]}],
     [:cancel_timers]} = ok(LocalTurnEnd.final_wait_elapsed(state))

    # Late evidence for the settled provider turn cannot reopen or extend it.
    assert {:ok, _state, [], []} = LocalTurnEnd.native(state, ended(native, "partial words late"))
  end

  test "speech with no words ends without text after the bounded wait" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))
    {state, [], [:finalize, :arm_final_wait]} = ok(LocalTurnEnd.hangover_elapsed(state))

    assert {:ok, _state, [{:turn_ended, [turn_ref: ^turn, text: "", endpointing: :local_gap]}],
            [:cancel_timers]} = LocalTurnEnd.final_wait_elapsed(state)
  end

  test "text without a local onset starts the turn and closes it after the resume window" do
    state = LocalTurnEnd.new(finalize?: true)

    {state, [{:speech_started, [turn_ref: turn]}, {:transcript, [turn_ref: turn, text: "hm"]}],
     [:arm_hangover]} = ok(LocalTurnEnd.native(state, transcript(make_ref(), "hm")))

    assert {:ok, _state, [], [:finalize, :arm_final_wait]} = LocalTurnEnd.hangover_elapsed(state)
  end

  test "empty and repeated provider text emits nothing and eager marks are ignored" do
    state = LocalTurnEnd.new(finalize?: true)
    native = make_ref()
    {state, [], []} = ok(LocalTurnEnd.native(state, transcript(native, "  ")))
    {state, [{:speech_started, _}], []} = ok(LocalTurnEnd.acoustic_started(state))
    {state, [{:transcript, _}], []} = ok(LocalTurnEnd.native(state, transcript(native, "same")))
    {state, [], []} = ok(LocalTurnEnd.native(state, transcript(native, "same")))

    eager = %Event{
      kind: :eager_turn_ended,
      turn_ref: native,
      text: "same",
      endpointing: :provider_semantic
    }

    assert {:ok, _state, [], []} = LocalTurnEnd.native(state, eager)
  end

  test "the turn end carries summed provider audio duration and the latest request identity" do
    state = LocalTurnEnd.new(finalize?: true)
    {state, [{:speech_started, [turn_ref: turn]}], []} = ok(LocalTurnEnd.acoustic_started(state))

    first = %{ended(make_ref(), "one") | audio_duration_ms: 20, provider_request_id: "req-1"}
    {state, [{:transcript, fields}], []} = ok(LocalTurnEnd.native(state, first))
    assert fields == [turn_ref: turn, text: "one", provider_request_id: "req-1"]

    second = %{ended(make_ref(), "two") | audio_duration_ms: 15, provider_request_id: "req-2"}
    {state, _emissions, []} = ok(LocalTurnEnd.native(state, second))
    {state, [], [:arm_hangover]} = ok(LocalTurnEnd.acoustic_ended(state))

    assert {:ok, _state, [{:turn_ended, ended_fields}], _actions} =
             LocalTurnEnd.hangover_elapsed(state)

    assert ended_fields == [
             turn_ref: turn,
             text: "one two",
             endpointing: :local_gap,
             provider_request_id: "req-2",
             audio_duration_ms: 35
           ]
  end

  test "invalid provider evidence fails with a fixed reason" do
    state = LocalTurnEnd.new(finalize?: true)
    assert {:error, :invalid_event} = LocalTurnEnd.native(state, %Event{kind: :transcript})
    assert {:error, :invalid_event} = LocalTurnEnd.native(state, :bogus)
  end

  defp ok({:ok, state, emissions, actions}), do: {state, emissions, actions}

  defp transcript(native, text), do: %Event{kind: :transcript, turn_ref: native, text: text}

  defp ended(native, text),
    do: %Event{kind: :turn_ended, turn_ref: native, text: text, endpointing: :provider_gap}
end
