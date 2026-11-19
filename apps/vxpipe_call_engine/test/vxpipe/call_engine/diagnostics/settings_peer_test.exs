defmodule Vxpipe.CallEngine.Diagnostics.SettingsPeerTest do
  use ExUnit.Case, async: false
  alias Vxpipe.CallEngine.DiagnosticSettingsPeer, as: Probe

  @tag timeout: 30_000
  test "independent workers revoke authority after a missed invalidation without sharing clocks" do
    first = peer(:first)
    second = peer(:second)
    assert call(first, :start, [0]) == {:enabled, 1}
    assert call(second, :start, [100_000]) == {:enabled, 1}
    assert call(first, :granted?)
    assert call(second, :granted?)

    # Both workers see the new durable value, but only one receives the hint.
    disabled = {:ok, %{enabled: false, revision: 2}}
    assert :ok = call(first, :write, [disabled])
    assert :ok = call(second, :write, [disabled])
    assert :ok = call(first, :suspend)
    assert :ok = call(first, :invalidate)
    assert call(first, :status) == {:unavailable, :invalidated}
    refute call(first, :granted?)
    assert :ok = call(first, :resume)
    assert :ok = call(first, :advance, [1_000])
    assert call(first, :refresh) == {:disabled, 2}

    # A disconnected/stalled reader has no push hint or successful refresh.
    assert :ok = call(second, :suspend)
    assert :ok = call(second, :advance, [102_999])
    assert call(second, :granted?)
    assert :ok = call(second, :advance, [103_000])
    assert call(second, :status) == {:unavailable, :expired_settings}
    refute call(second, :granted?)
    assert :ok = call(second, :resume)
    assert :ok = call(second, :advance, [104_000])
    assert call(second, :refresh) == {:disabled, 2}

    # Reconnection cannot use a stale enabled revision; a newer enable can grant.
    assert :ok = call(second, :write, [{:ok, %{enabled: true, revision: 1}}])
    assert :ok = call(second, :advance, [105_000])
    assert call(second, :refresh) == {:disabled, 2}
    refute call(second, :granted?)
    assert :ok = call(second, :write, [{:ok, %{enabled: true, revision: 3}}])
    assert :ok = call(second, :advance, [106_000])
    assert call(second, :refresh) == {:enabled, 3}
    assert call(second, :granted?)
    refute call(first, :granted?)
  end

  defp peer(id) do
    options = %{connection: :standard_io, args: [~c"+S", ~c"2:2", ~c"-pa" | :code.get_path()]}
    start_supervised!(%{id: id, start: {:peer, :start_link, [options]}})
  end

  defp call(peer, function, args \\ []), do: :peer.call(peer, Probe, function, args, 5_000)
end
