defmodule Vxpipe.CallEngine.Speech.ResponseStartsTest do
  use ExUnit.Case, async: true

  alias Vxpipe.CallEngine.Speech.{Event, ResponseStarts}

  test "ordinals advance monotonically with gaps and never reopen a retired index" do
    context = make_ref()
    first = event(1, context)
    third = event(3, context)
    owner = ResponseStarts.new()
    {:ok, owner} = ResponseStarts.accept(owner, first)
    {:ok, owner} = ResponseStarts.accept(owner, third)
    assert owner.high_water == 3
    assert {:error, :stale_response} = ResponseStarts.accept(owner, event(2, context))
    assert {:error, :stale_response} = ResponseStarts.accept(owner, event(3, context))
    assert {:error, :stale_response} = ResponseStarts.accept(owner, first)

    assert {:error, :stale_response} =
             ResponseStarts.accept(owner, %{third | response_index: 4})

    assert owner.high_water == 3
  end

  test "exact acknowledgement and oldest-first grant consume only the matching response" do
    context = make_ref()
    first = event(1, context)
    second = event(2, context)
    {:ok, owner} = ResponseStarts.accept(ResponseStarts.new(), first)
    {:ok, owner} = ResponseStarts.accept(owner, second)
    assert {:error, :response_not_acknowledged} = ResponseStarts.grant(owner, first.turn_ref)
    {:ok, owner} = ResponseStarts.acknowledge(owner, second)
    assert {:error, :busy} = ResponseStarts.grant(owner, second.turn_ref)

    assert {:error, :stale_response} =
             ResponseStarts.acknowledge(owner, %{first | response_context: make_ref()})

    {:ok, owner} = ResponseStarts.acknowledge(owner, first)
    assert {:ok, owner, ^context} = ResponseStarts.grant(owner, first.turn_ref)
    assert {:error, :stale_response} = ResponseStarts.grant(owner, first.turn_ref)
    assert {:ok, owner, ^context} = ResponseStarts.grant(owner, second.turn_ref)
    assert ResponseStarts.pending_count(owner) == 0
    assert owner.high_water == 2
  end

  test "rejection needs acknowledgement and disposes only the named pending response" do
    context = make_ref()
    first = event(1, context)
    second = event(2, context)
    {:ok, owner} = ResponseStarts.accept(ResponseStarts.new(), first)
    {:ok, owner} = ResponseStarts.accept(owner, second)
    assert {:error, :response_not_acknowledged} = ResponseStarts.reject(owner, first.turn_ref)
    {:ok, owner} = ResponseStarts.acknowledge(owner, first)
    {:ok, owner} = ResponseStarts.acknowledge(owner, second)
    assert {:ok, owner, ^context} = ResponseStarts.reject(owner, first.turn_ref)
    assert {:error, :stale_response} = ResponseStarts.reject(owner, first.turn_ref)
    assert {:ok, owner, ^context} = ResponseStarts.grant(owner, second.turn_ref)
    assert {:error, :stale_response} = ResponseStarts.accept(owner, first)
  end

  test "sixteen pending starts are bounded and capacity recovers after disposition" do
    context = make_ref()

    {owner, starts} =
      Enum.reduce(1..16, {ResponseStarts.new(), []}, fn index, {owner, starts} ->
        start = event(index, context)
        {:ok, owner} = ResponseStarts.accept(owner, start)
        {:ok, owner} = ResponseStarts.acknowledge(owner, start)
        {owner, [start | starts]}
      end)

    assert ResponseStarts.pending_count(owner) == 16
    assert {:error, :response_overflow} = ResponseStarts.accept(owner, event(17, context))
    oldest = List.last(starts)
    {:ok, owner, ^context} = ResponseStarts.reject(owner, oldest.turn_ref)
    {:ok, owner} = ResponseStarts.accept(owner, event(18, context))
    assert owner.high_water == 18
    assert ResponseStarts.pending_count(owner) == 16
  end

  test "forty sequentially settled starts need no retired-reference set" do
    context = make_ref()

    owner =
      Enum.reduce(1..40, ResponseStarts.new(), fn index, owner ->
        start = event(index, context)
        {:ok, owner} = ResponseStarts.accept(owner, start)
        {:ok, owner} = ResponseStarts.acknowledge(owner, start)
        {:ok, owner, ^context} = ResponseStarts.grant(owner, start.turn_ref)
        assert ResponseStarts.pending_count(owner) == 0
        owner
      end)

    assert owner.high_water == 40
    assert owner.pending == %{}
  end

  test "maximum signed ordinal cannot wrap or be reused" do
    context = make_ref()
    maximum = 9_223_372_036_854_775_807
    last = event(maximum, context)
    {:ok, owner} = ResponseStarts.accept(ResponseStarts.new(), last)
    {:ok, owner} = ResponseStarts.acknowledge(owner, last)
    {:ok, owner, ^context} = ResponseStarts.grant(owner, last.turn_ref)
    assert {:error, :response_overflow} = ResponseStarts.accept(owner, event(1, context))
  end

  defp event(index, context) do
    {:ok, event} =
      Event.build(:response_started,
        turn_ref: make_ref(),
        response_index: index,
        response_context: context
      )

    event
  end
end
