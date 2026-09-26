defmodule Vxpipe.CallEngine.Speech.Duplex.BurstResponsesTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.Duplex.BurstResponses

  test "new validates configuration and defaults the unadmitted bound to four" do
    assert {:ok, br} = BurstResponses.new()
    assert br.maximum_unadmitted == 4
    assert {:ok, br} = BurstResponses.new(maximum_unadmitted: 2)
    assert br.maximum_unadmitted == 2
    assert {:error, :invalid_configuration} = BurstResponses.new(maximum_unadmitted: 0)
    assert {:error, :invalid_configuration} = BurstResponses.new(:nope)
  end

  test "input_accepted records the latest context and ignores non references" do
    {:ok, br} = BurstResponses.new()
    context = make_ref()

    assert {br, []} = BurstResponses.input_accepted(br, context)
    assert br.latest_context == context

    assert {^br, []} = BurstResponses.input_accepted(br, :not_a_context)
  end

  test "a burst before any accepted input drops the segment and never announces" do
    {:ok, br} = BurstResponses.new()
    seg_ref = make_ref()

    assert {^br, [{:drop_segment, ^seg_ref}]} = BurstResponses.burst_opened(br, seg_ref)
  end

  test "each burst announces its own response with an increasing index" do
    {:ok, br} = BurstResponses.new()
    context = make_ref()
    {br, []} = BurstResponses.input_accepted(br, context)

    first_seg = make_ref()

    assert {br, [{:announce, first_turn, 1, ^context}]} =
             BurstResponses.burst_opened(br, first_seg)

    assert is_reference(first_turn)

    second_seg = make_ref()

    assert {_br, [{:announce, second_turn, 2, ^context}]} =
             BurstResponses.burst_opened(br, second_seg)

    assert second_turn != first_turn
  end

  test "a later accepted input becomes the context of the next burst" do
    {:ok, br} = BurstResponses.new()
    first_context = make_ref()
    {br, []} = BurstResponses.input_accepted(br, first_context)
    {br, [{:announce, _turn, 1, ^first_context}]} = BurstResponses.burst_opened(br, make_ref())

    second_context = make_ref()
    {br, []} = BurstResponses.input_accepted(br, second_context)

    assert {_br, [{:announce, _turn, 2, ^second_context}]} =
             BurstResponses.burst_opened(br, make_ref())
  end

  test "announcements beyond the unadmitted bound fail explicitly" do
    {:ok, br} = BurstResponses.new(maximum_unadmitted: 2)
    {br, []} = BurstResponses.input_accepted(br, make_ref())

    {br, [{:announce, _, 1, _}]} = BurstResponses.burst_opened(br, make_ref())
    {br, [{:announce, _, 2, _}]} = BurstResponses.burst_opened(br, make_ref())
    assert {:error, :pending_response_overflow} = BurstResponses.burst_opened(br, make_ref())
  end

  test "admission then close admits the segment and completes the response" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    seg_ref = make_ref()
    {br, [{:announce, turn, 1, _}]} = BurstResponses.burst_opened(br, seg_ref)

    output_ref = make_ref()

    assert {br, [{:admit_segment, ^seg_ref, ^output_ref}]} =
             BurstResponses.admitted(br, turn, output_ref)

    assert {_br, [{:complete, ^turn, ^output_ref}]} = BurstResponses.burst_closed(br, seg_ref)
  end

  test "a burst that closes before admission admits and completes when admission arrives" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    seg_ref = make_ref()
    {br, [{:announce, turn, 1, _}]} = BurstResponses.burst_opened(br, seg_ref)

    assert {br, []} = BurstResponses.burst_closed(br, seg_ref)

    output_ref = make_ref()

    assert {_br, [{:admit_segment, ^seg_ref, ^output_ref}, {:complete, ^turn, ^output_ref}]} =
             BurstResponses.admitted(br, turn, output_ref)
  end

  test "a burst yielded before admission completes empty when admission arrives" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    {br, [{:announce, turn, 1, _}]} = BurstResponses.burst_opened(br, make_ref())

    assert {br, []} = BurstResponses.yielded(br)

    output_ref = make_ref()

    assert {_br, [{:complete_empty, ^turn, ^output_ref}]} =
             BurstResponses.admitted(br, turn, output_ref)
  end

  test "discard drops the segment, plays nothing and ignores a later admission" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    seg_ref = make_ref()
    {br, [{:announce, turn, 1, _}]} = BurstResponses.burst_opened(br, seg_ref)

    assert {br, [{:drop_segment, ^seg_ref}]} = BurstResponses.discarded(br, turn)
    assert {^br, []} = BurstResponses.admitted(br, turn, make_ref())
    assert {^br, []} = BurstResponses.burst_closed(br, seg_ref)
  end

  test "yield marks the newest open burst only" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    {br, [{:announce, first, 1, _}]} = BurstResponses.burst_opened(br, make_ref())
    {br, [{:announce, second, 2, _}]} = BurstResponses.burst_opened(br, make_ref())

    assert {br, []} = BurstResponses.yielded(br)
    refute br.bursts[first].yielded?
    assert br.bursts[second].yielded?
  end

  test "turn_for_segment resolves the announcing turn" do
    {:ok, br} = BurstResponses.new()
    {br, []} = BurstResponses.input_accepted(br, make_ref())
    seg_ref = make_ref()
    {br, [{:announce, turn, 1, _}]} = BurstResponses.burst_opened(br, seg_ref)

    assert {:ok, ^turn} = BurstResponses.turn_for_segment(br, seg_ref)
    assert :error = BurstResponses.turn_for_segment(br, make_ref())
  end
end
