defmodule Vxpipe.Console.HTTPByteRangeTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Console.HTTPByteRange

  test "selects full, bounded, open-ended, and suffix responses" do
    assert {:ok, %{first: 0, last: 55, status: 200}} = HTTPByteRange.parse(nil, 56)

    assert {:ok, %{first: 44, last: 47, status: 206}} =
             HTTPByteRange.parse("bytes=44-47", 56)

    assert {:ok, %{first: 52, last: 55, status: 206}} =
             HTTPByteRange.parse("bytes=52-", 56)

    assert {:ok, %{first: 52, last: 55, status: 206}} =
             HTTPByteRange.parse("bytes=-4", 56)
  end

  test "rejects multiple, malformed, and unsatisfiable ranges" do
    assert {:error, :range_not_satisfiable} = HTTPByteRange.parse("bytes=0-1,4-5", 56)
    assert {:error, :range_not_satisfiable} = HTTPByteRange.parse("items=0-1", 56)
    assert {:error, :range_not_satisfiable} = HTTPByteRange.parse("bytes=56-", 56)
    assert {:error, :range_not_satisfiable} = HTTPByteRange.parse("bytes=-0", 56)
  end
end
