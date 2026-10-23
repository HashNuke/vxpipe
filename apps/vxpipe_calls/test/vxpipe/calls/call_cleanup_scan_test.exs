defmodule Vxpipe.Calls.CallCleanupScanTest do
  use ExUnit.Case, async: true
  alias Vxpipe.Calls

  test "passes bounded internal cursors to storage and preserves the page" do
    cursor = %{after_id: 12, through_id: 20}
    result = {:ok, %{items: [%{call_id: "call"}], next_cursor: nil}}
    options = [call_repository: {__MODULE__, {self(), result}}]
    assert ^result = Calls.scan_call_cleanup(cursor, 25, options)
    assert_received {:scan, ^cursor, 25}
  end

  test "invalid limits and cursors cannot reach storage" do
    options = [call_repository: {__MODULE__, :must_not_call}]

    for limit <- [0, -1, 101, 1.5, "10"],
        do: assert({:error, :invalid_cleanup_scan} = Calls.scan_call_cleanup(nil, limit, options))

    for cursor <- [
          %{},
          %{after_id: -1, through_id: 20},
          %{after_id: 21, through_id: 20},
          %{after_id: 0, through_id: "20"},
          %{after_id: 0, through_id: 20, extra: true},
          "12"
        ],
        do: assert({:error, :invalid_cleanup_scan} = Calls.scan_call_cleanup(cursor, 10, options))
  end

  test "storage faults and invalid page shapes return a sanitized unavailable result" do
    for result <- [
          :raise,
          :exit,
          {:error, "private"},
          {:ok, :invalid},
          {:ok, %{items: List.duplicate(%{}, 2), next_cursor: nil}},
          {:ok, %{items: [], next_cursor: %{after_id: 20, through_id: 1}}}
        ] do
      assert {:error, :call_cleanup_unavailable} =
               Calls.scan_call_cleanup(nil, 1, call_repository: {__MODULE__, result})
    end
  end

  def scan_call_cleanup(:must_not_call, _, _), do: flunk("unexpected storage")
  def scan_call_cleanup(:raise, _, _), do: raise("private")
  def scan_call_cleanup(:exit, _, _), do: exit(:private)

  def scan_call_cleanup({observer, result}, cursor, limit) when is_pid(observer) do
    send(observer, {:scan, cursor, limit})
    result
  end

  def scan_call_cleanup(result, _, _), do: result
end
