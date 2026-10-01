defmodule Vxpipe.Providers.ElevenLabs.ScribeTurnTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Providers.ElevenLabs.ScribeTurn

  test "a settled transcript segment preserves the caller turn until its acoustic endpoint" do
    turn_ref = make_ref()
    turn = ScribeTurn.new(turn_ref)
    audio = :binary.copy(<<1, 0>>, 16_000)

    turn =
      Enum.reduce(1..19, turn, fn _second, state ->
        assert {:ok, state, [{:audio, ^audio}]} = ScribeTurn.push_audio(state, audio)
        state
      end)

    assert {:ok, turn, [{:audio, ^audio}, :commit]} = ScribeTurn.push_audio(turn, audio)

    assert {:ok, turn, [{:transcript, ^turn_ref, "First segment."}]} =
             ScribeTurn.committed(turn, "First segment.")

    assert {:ok, turn, [{:audio, ^audio}]} = ScribeTurn.push_audio(turn, audio)
    assert {:ok, turn, [:commit]} = ScribeTurn.end_turn(turn)

    assert {:ok, _turn,
            [
              {:transcript, ^turn_ref, "First segment. Second segment."},
              {:turn_ended, ^turn_ref, "First segment. Second segment."}
            ]} = ScribeTurn.committed(turn, "Second segment.")
  end

  test "crossing the segment budget retains the rest of the accepted chunk before final settlement" do
    turn_ref = make_ref()
    audio = :binary.copy(<<1, 0>>, 16_000)

    turn =
      Enum.reduce(1..19, ScribeTurn.new(turn_ref), fn _second, state ->
        assert {:ok, state, [{:audio, ^audio}]} = ScribeTurn.push_audio(state, audio)
        state
      end)

    shorter = :binary.copy(<<1, 0>>, 15_840)
    assert {:ok, turn, [{:audio, ^shorter}]} = ScribeTurn.push_audio(turn, shorter)
    <<prefix::binary-size(320), remainder::binary>> = audio
    assert {:ok, turn, [{:audio, ^prefix}, :commit]} = ScribeTurn.push_audio(turn, audio)
    assert {:error, :busy} = ScribeTurn.push_audio(turn, <<0, 0>>)
    assert {:ok, turn, []} = ScribeTurn.end_turn(turn)

    assert {:ok, turn, [{:transcript, ^turn_ref, "First."}, {:audio, ^remainder}, :commit]} =
             ScribeTurn.committed(turn, "First.")

    assert {:ok, turn,
            [
              {:transcript, ^turn_ref, "First. Tail."},
              {:turn_ended, ^turn_ref, "First. Tail."}
            ]} = ScribeTurn.committed(turn, "Tail.")

    assert {:ok, _turn, []} = ScribeTurn.end_turn(turn)
    assert {:error, :input_closed} = ScribeTurn.push_audio(turn, <<0, 0>>)
    assert {:error, :unexpected_segment} = ScribeTurn.committed(turn, "late text")
  end

  test "partials replace only the current segment and never establish activity or completion" do
    turn_ref = make_ref()
    turn = ScribeTurn.new(turn_ref)
    audio = :binary.copy(<<1, 0>>, 16_000)

    turn =
      Enum.reduce(1..20, turn, fn _second, state ->
        assert {:ok, state, _actions} = ScribeTurn.push_audio(state, audio)
        state
      end)

    assert {:ok, turn, [{:transcript, ^turn_ref, "Committed."}]} =
             ScribeTurn.committed(turn, "Committed.")

    assert {:ok, turn, [{:audio, ^audio}]} = ScribeTurn.push_audio(turn, audio)

    assert {:ok, turn, [{:transcript, ^turn_ref, "Committed. replace me"}]} =
             ScribeTurn.partial(turn, "replace me")

    assert {:ok, turn, [{:transcript, ^turn_ref, "Committed. replacement"}]} =
             ScribeTurn.partial(turn, "replacement")

    assert {:ok, turn, []} = ScribeTurn.partial(turn, "replacement")
    assert {:ok, turn, []} = ScribeTurn.partial(turn, "")
    assert {:ok, turn, [:commit]} = ScribeTurn.end_turn(turn)

    assert {:ok, _turn,
            [
              {:transcript, ^turn_ref, "Committed. Final."},
              {:turn_ended, ^turn_ref, "Committed. Final."}
            ]} = ScribeTurn.committed(turn, "Final.")
  end

  test "bounded waiting input is never accepted twice or finalized from an unsolicited segment" do
    turn_ref = make_ref()
    turn = ScribeTurn.new(turn_ref)
    assert {:error, :unexpected_segment} = ScribeTurn.committed(turn, "unsolicited")
    assert {:error, :unexpected_segment} = ScribeTurn.partial(turn, "no submitted audio")
    assert {:error, :invalid_audio} = ScribeTurn.push_audio(turn, <<1>>)
    assert {:error, :invalid_audio} = ScribeTurn.push_audio(turn, "")

    assert {:ok, turn, [{:audio, <<1, 0>>}]} = ScribeTurn.push_audio(turn, <<1, 0>>)
    assert {:ok, turn, [:commit]} = ScribeTurn.end_turn(turn)
    assert {:ok, turn, []} = ScribeTurn.end_turn(turn)
    assert {:error, :input_closed} = ScribeTurn.push_audio(turn, <<2, 0>>)
    assert {:error, :invalid_segment} = ScribeTurn.committed(turn, <<255>>)
    assert {:error, :invalid_segment} = ScribeTurn.committed(turn, String.duplicate("x", 65_537))

    assert {:ok, _turn, [{:transcript, ^turn_ref, ""}, {:turn_ended, ^turn_ref, ""}]} =
             ScribeTurn.committed(turn, "")
  end

  test "inspection never discloses recognized text or retained input" do
    turn = ScribeTurn.new(make_ref())
    assert {:ok, turn, _actions} = ScribeTurn.push_audio(turn, <<1, 0>>)
    assert {:ok, turn, _actions} = ScribeTurn.end_turn(turn)
    assert {:ok, turn, _actions} = ScribeTurn.committed(turn, "private-recognized-phrase")
    refute inspect(turn) =~ "private-recognized-phrase"
  end

  test "the transcript budget applies across commits and replaceable partials" do
    turn_ref = make_ref()
    audio = :binary.copy(<<1, 0>>, 16_000)

    turn =
      Enum.reduce(1..20, ScribeTurn.new(turn_ref), fn _second, state ->
        assert {:ok, state, _actions} = ScribeTurn.push_audio(state, audio)
        state
      end)

    prefix = String.duplicate("x", 65_530)

    assert {:ok, turn, [{:transcript, ^turn_ref, ^prefix}]} =
             ScribeTurn.committed(turn, prefix)

    assert {:ok, turn, [{:audio, ^audio}]} = ScribeTurn.push_audio(turn, audio)
    assert {:error, :invalid_segment} = ScribeTurn.partial(turn, "too much text")
    assert {:error, :invalid_segment} = ScribeTurn.partial(turn, <<255>>)
    assert {:ok, turn, [:commit]} = ScribeTurn.end_turn(turn)
    assert {:error, :invalid_segment} = ScribeTurn.committed(turn, "too much text")

    assert {:ok, _turn, [{:transcript, ^turn_ref, ^prefix}, {:turn_ended, ^turn_ref, ^prefix}]} =
             ScribeTurn.committed(turn, "   ")
  end
end
