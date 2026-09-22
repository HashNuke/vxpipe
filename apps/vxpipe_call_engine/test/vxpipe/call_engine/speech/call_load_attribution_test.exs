defmodule Vxpipe.CallEngine.Speech.CallLoadAttributionTest do
  use ExUnit.Case, async: true
  alias Vxpipe.CallEngine.CallLoad.Attribution

  test "sink before public onset cannot advance or relabel phase two" do
    state = Attribution.begin_input(Attribution.new(), 2, 100)
    {state, 100} = Attribution.observe(state, :sink, "sink-2", 200)
    state = Attribution.finish_input(state, 2)
    refute Attribution.ready?(state)

    assert_raise ArgumentError, ~r/unsettled attribution/, fn ->
      Attribution.begin_input(state, 3, 220)
    end

    {state, 150} = Attribution.observe(state, :caller, "caller-2", 250)
    refute Attribution.ready?(state)
    {state, 200} = Attribution.observe(state, :public, "public-2", 300)
    assert Attribution.ready?(state)
    state = Attribution.begin_input(state, 3, 400)
    assert Attribution.elapsed(state, :public, "public-2", 450) == 350
    assert Attribution.elapsed(state, :sink, "sink-2", 450) == 350
    assert Attribution.elapsed(state, :caller, "caller-2", 450) == 350

    assert_raise ArgumentError, ~r/duplicate correlation/, fn ->
      Attribution.observe(state, :public, "public-2", 460)
    end

    assert_raise ArgumentError, ~r/unknown correlation/, fn ->
      Attribution.elapsed(state, :public, "unknown", 470)
    end

    {state, 100} = Attribution.observe(state, :sink, "sink-3", 500)
    assert Attribution.elapsed(state, :sink, "sink-3", 550) == 150
  end

  test "late caller onset also holds the gate and namespaces remain independent" do
    state = Attribution.begin_input(Attribution.new(), 2, 100)
    {state, 50} = Attribution.observe(state, :sink, "shared-id", 150)
    {state, 100} = Attribution.observe(state, :public, "shared-id", 200)
    state = Attribution.finish_input(state, 2)
    refute Attribution.ready?(state)
    {state, 150} = Attribution.observe(state, :caller, "shared-id", 250)
    assert Attribution.ready?(state)

    assert_raise ArgumentError, ~r/uncorrelated extra caller onset/, fn ->
      Attribution.observe(state, :caller, "another-id", 260)
    end

    assert_raise ArgumentError, ~r/uncorrelated input completion/, fn ->
      Attribution.finish_input(state, 3)
    end
  end
end
