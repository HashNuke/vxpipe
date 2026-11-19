defmodule Vxpipe.CallEngine.Speech.ActivityBoundaryTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.ActivityBoundary

  test "finalized samples exclude windows that can still produce backdated boundaries" do
    state = ActivityBoundary.new()
    assert ActivityBoundary.finalized_samples(state) == 0
    assert {:ok, state, []} = ActivityBoundary.push(state, 0.1)

    state =
      Enum.reduce(1..3, state, fn _, current ->
        assert {:ok, current, []} = ActivityBoundary.push(current, 0.8)
        assert ActivityBoundary.finalized_samples(current) == 512
        current
      end)

    assert {:ok, state, [{:speech_started, 512}]} = ActivityBoundary.push(state, 0.8)
    assert ActivityBoundary.finalized_samples(state) == 2_560

    state =
      Enum.reduce(1..15, state, fn _, current ->
        assert {:ok, current, []} = ActivityBoundary.push(current, 0.1)
        assert ActivityBoundary.finalized_samples(current) == 2_560
        current
      end)

    assert {:ok, state, [{:speech_ended, 2_560}]} = ActivityBoundary.push(state, 0.1)
    assert ActivityBoundary.finalized_samples(state) == 10_752
    assert ActivityBoundary.finalized_samples(ActivityBoundary.reset(state)) == 0
  end

  test "discarded onset and silence candidates release their finalized prefix" do
    assert {:ok, state, []} = ActivityBoundary.push(ActivityBoundary.new(), 0.8)
    assert ActivityBoundary.finalized_samples(state) == 0
    assert {:ok, state, []} = ActivityBoundary.push(state, 0.1)
    assert ActivityBoundary.finalized_samples(state) == 1_024

    state =
      Enum.reduce(1..4, state, fn _, current ->
        {:ok, current, _events} = ActivityBoundary.push(current, 0.8)
        current
      end)

    assert {:ok, state, []} = ActivityBoundary.push(state, 0.1)
    assert ActivityBoundary.finalized_samples(state) == 3_072
    assert {:ok, state, []} = ActivityBoundary.push(state, 0.8)
    assert ActivityBoundary.finalized_samples(state) == 4_096
  end

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
