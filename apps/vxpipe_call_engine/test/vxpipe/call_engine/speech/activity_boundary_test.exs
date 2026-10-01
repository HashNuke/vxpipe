defmodule Vxpipe.CallEngine.Speech.ActivityBoundaryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.ActivityBoundary

  test "speech onset and endpoint require confirmed classified PCM" do
    boundary = ActivityBoundary.new()

    boundary =
      Enum.reduce(1..3, boundary, fn _, state ->
        assert {:ok, state, []} = ActivityBoundary.push(state, 0.8)
        state
      end)

    assert {:ok, boundary, [{:speech_started, 0}]} = ActivityBoundary.push(boundary, 0.8)

    boundary =
      Enum.reduce(1..15, boundary, fn _, state ->
        assert {:ok, state, []} = ActivityBoundary.push(state, 0.1)
        state
      end)

    assert {:ok, _boundary, [{:speech_ended, 2_048}]} = ActivityBoundary.push(boundary, 0.1)
  end

  test "unconfirmed onset is discarded and hysteresis preserves resumed speech" do
    state = ActivityBoundary.new()
    assert {:ok, state, []} = ActivityBoundary.push(state, 0.8)
    assert {:ok, state, []} = ActivityBoundary.push(state, 0.4)

    state =
      Enum.reduce(1..3, state, fn _, current ->
        assert {:ok, current, []} = ActivityBoundary.push(current, 0.8)
        current
      end)

    assert {:ok, state, [{:speech_started, 1_024}]} = ActivityBoundary.push(state, 0.5)

    state =
      Enum.reduce(1..15, state, fn _, current ->
        assert {:ok, current, []} = ActivityBoundary.push(current, 0.1)
        current
      end)

    assert {:ok, state, []} = ActivityBoundary.push(state, 0.35)

    state =
      Enum.reduce(1..15, state, fn _, current ->
        assert {:ok, current, []} = ActivityBoundary.push(current, 0.1)
        current
      end)

    assert {:ok, state, [{:speech_ended, 11_264}]} = ActivityBoundary.push(state, 0.1)
    assert {:ok, _state, []} = ActivityBoundary.push(state, 0.1)
  end

  test "invalid classifications do not advance the acoustic cursor" do
    state = ActivityBoundary.new()

    for probability <- [-0.1, 1.1, :speech, "0.5"] do
      assert {:error, :invalid_probability} = ActivityBoundary.push(state, probability)
    end

    assert state.samples == 0
  end

  test "reset drops confirmation and positions from the previous permission interval" do
    assert {:ok, state, []} = ActivityBoundary.push(ActivityBoundary.new(), 0.8)
    assert ActivityBoundary.reset(state) == ActivityBoundary.new()
  end
end
