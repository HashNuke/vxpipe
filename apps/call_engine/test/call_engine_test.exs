defmodule CallEngineTest do
  use ExUnit.Case
  doctest CallEngine

  test "greets the world" do
    assert CallEngine.hello() == :world
  end
end
